import AppKit
import Combine
import WritingCore

/// Ties the focused input to the checkers, underlines, hover card, icon and popover.
@MainActor
final class Controller {
    var onSlackNeedsRestart: ((Bool) -> Void)?

    private let auth: AuthMonitor
    private let watcher = FocusWatcher()
    private let local = LocalChecker()
    private let checkLane: ClaudeLane
    private let actionLanes: [WritingAction: ClaudeLane]
    private let checker: SentenceChecker
    private let overlay = OverlayPanel()
    private let card = HoverCard()
    private let icon = IconPanel()
    private let popover = ActionPopover()
    private let menu = LiquidMenu()
    /// The selected range a Rephrase or Shorten result will replace; nil means the whole input.
    private var target: NSRange?

    private var marks: [Mark] = []
    private var rects: [[CGRect]] = []
    private var hot: Int?
    private var hideCard: Task<Void, Never>?
    private var mouseMonitor: Any?
    private var authSubscription: AnyCancellable?
    private var lastSummary = ""
    /// The text and selection the current marks were computed from.
    private var markedText = ""
    private var markedSelection: NSRange?
    private var isWriting = false
    /// While Fix Everything's celebration plays, redraws leave the dot and underlines alone.
    private var celebrating = false
    /// Rephrase or Make It Shorter is waiting on Haiku; the dot thinks meanwhile.
    private var actionRunning = false { didSet { redraw() } }
    private var lastEdit: Date?
    private var settleTask: Task<Void, Never>?
    private var idleTimer: Timer?

    /// Stable per mistake while typing elsewhere moves it, so its underline doesn't fade in again.
    private var markKeys: [String] {
        let text = (watcher.input?.text ?? "") as NSString
        var seen: [String: Int] = [:]
        return marks.map { m in
            let base = NSMaxRange(m.range) <= text.length ? "\(text.substring(with: m.range))→\(m.fix)" : m.fix
            seen[base, default: 0] += 1
            return "\(base)#\(seen[base]!)"
        }
    }

    private var connected: Bool { if case .connected = auth.state { true } else { false } }

    init(auth: AuthMonitor) {
        self.auth = auth
        let exe = ClaudePaths.executable, cwd = ClaudePaths.workingDirectory
        checkLane = ClaudeLane(executable: exe, systemPrompt: Prompts.check, workingDirectory: cwd, onTokens: Usage.record)
        actionLanes = Dictionary(uniqueKeysWithValues: [WritingAction.rephrase, .shorten].map {
            ($0, ClaudeLane(executable: exe, systemPrompt: Prompts.action($0), workingDirectory: cwd, onTokens: Usage.record))
        })
        checker = SentenceChecker(lane: checkLane)
    }

    var currentSite: String? { watcher.currentSite }
    func recheckBlocked() { watcher.recheck() }

    func start() {
        watcher.onFocus = { [weak self] _ in self?.refresh(textChanged: true) }
        watcher.onTextChange = { [weak self] in self?.refresh(textChanged: true) }
        watcher.onCaretChange = { [weak self] in self?.refresh(textChanged: false) }
        watcher.onGeometryWillChange = { [weak self] in
            self?.overlay.hide(); self?.card.hide(); self?.icon.hide()
        }
        watcher.onGeometryChange = { [weak self] in self?.redraw() }
        watcher.onTick = { [weak self] in self?.checkScroll() }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                for lane in self?.actionLanes.values.map({ $0 }) ?? [] { Task { await lane.shutDownIfIdle(for: 300) } }
            }
        }
        watcher.onSlackNeedsRestart = { [weak self] in self?.onSlackNeedsRestart?($0) }
        checker.onChange = { [weak self] in self?.refresh(textChanged: false) }
        checker.onAuthError = { [weak self] in Task { await self?.auth.refresh() } }
        icon.onClick = { [weak self] in self?.openPopover() }
        card.onApply = { [weak self] in self?.apply($0) }
        card.onHoverChange = { [weak self] inside in
            if inside { self?.hideCard?.cancel() } else { self?.scheduleHideCard() }
        }
        popover.onRun = { [weak self] action, text in
            guard let self, let lane = self.actionLanes[action] else { return text }
            self.actionRunning = true
            defer { self.actionRunning = false }
            Log.write("action \(action) start len=\((text as NSString).length)")
            do {
                let out = cleanResult(try await lane.send(text, timeout: .seconds(10)), original: text)
                Log.write("action \(action) ok outLen=\((out as NSString).length)")
                return out
            } catch {
                Log.write("action \(action) failed: \((error as? ClaudeError)?.logName ?? "\(type(of: error))")")
                throw error
            }
        }
        popover.onReplace = { [weak self] action, before, after in await self?.replace(action, before: before, after: after) }
        popover.onConnect = { [weak self] in self?.auth.startConnectFlow() }
        popover.onClose = { [weak self] in self?.watcher.input?.activate() }
        authSubscription = auth.$state.sink { [weak self] _ in
            DispatchQueue.main.async { self?.authChanged() }
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved(NSEvent.mouseLocation) }
        }
        watcher.start()
        Task { await checkLane.warmUp() }
    }

    private func authChanged() {
        checker.enabled = connected
        if connected {
            popover.connected()
            Task { await checkLane.warmUp() }
        }
        refresh(textChanged: false)
    }

    private func refresh(textChanged: Bool) {
        guard let input = watcher.input else {
            marks = []; rects = []; hot = nil
            overlay.hide(); card.hide(); icon.hide()
            return
        }
        let text = input.text, selected = input.selectedRange
        let ns = text as NSString
        let caret = selected.map { $0.location + $0.length }
        let selection = selected.flatMap { $0.length > 0 && NSMaxRange($0) <= ns.length ? $0 : nil }
        if textChanged {
            lastEdit = Date()
            // When typing pauses, check again so the word at the caret gets its underline.
            settleTask?.cancel()
            settleTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1600))
                guard !Task.isCancelled else { return }
                self?.refresh(textChanged: false)
            }
            icon.noteTyping()
            checker.textChanged(text)
            card.hide()
            hot = nil
        }
        let skip = protectedRanges(in: text)
        let haiku = (connected ? checker.marks(for: text) : []).filter { m in !skip.contains { NSIntersectionRange($0, m.range).length > 0 } }
        let typing = isTyping(lastEdit: lastEdit, now: Date())
        let spelling = local.marks(text: text, caret: caret, focused: typing).filter { m in
            trustsLocalSpelling(of: ns.substring(with: m.range), connected: connected)
        }.map { m in
            guard let better = haiku.first(where: { $0.range == m.range }) else { return m }
            return Mark(range: m.range, fix: matchCase(of: ns.substring(with: m.range), better.fix), kind: .spelling)
        }
        let touchesCaret: (NSRange) -> Bool = { r in typing && (caret.map { $0 >= r.location && $0 <= NSMaxRange(r) } ?? false) }
        let extra = haiku.filter { h in
            !touchesCaret(h.range) && !spelling.contains { NSIntersectionRange($0.range, h.range).length > 0 }
        }.map { Mark(range: $0.range, fix: matchCase(of: ns.substring(with: $0.range), $0.fix), kind: $0.kind) }
        marks = (spelling + extra).sorted { $0.range.location < $1.range.location }
        markedText = text
        markedSelection = selection
        redraw()
    }

    /// Redraws from the last refresh. Positions are read again; the text is not.
    private func redraw() {
        guard let input = watcher.input else { return }
        if celebrating { return }
        if isWriting { overlay.hide(); icon.hide(); return }
        let ns = markedText as NSString
        let first = ns.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted)
        let all = input.rects(for: marks.map(\.range) + (first.location == NSNotFound ? [] : [first]))
        rects = Array(all.prefix(marks.count))
        let firstLetter = first.location == NSNotFound ? nil : all.last?.first
        let summary = "marks=\(marks.count) placed=\(rects.filter { !$0.isEmpty }.count) len=\(ns.length) checking=\(checker.isChecking)"
        if summary != lastSummary { Log.write("draw \(input.target) \(summary)"); lastSummary = summary }
        overlay.show(rects: rects, keys: markKeys, hot: hot)
        guard !marks.isEmpty || markedSelection != nil else {
            if !popover.isOpen && !menu.isOpen { icon.hide() }
            return
        }
        icon.pin(firstLetter: firstLetter, input: input.frame, rightToLeft: isRightToLeft(markedText))
        icon.update(count: marks.count, checking: checker.isChecking, working: actionRunning, connected: connected)
    }

    /// Scrolling inside an input changes neither its text nor its frame, so compare one underline's position.
    private func checkScroll() {
        guard let input = watcher.input, !isWriting, let first = marks.first else { return }
        if input.rects(for: [first.range]).first?.first != rects.first?.first { redraw() }
    }

    private func mouseMoved(_ point: CGPoint) {
        guard watcher.input != nil, !popover.isOpen, !menu.isOpen, !isWriting else { return }
        let hit = rects.firstIndex { group in
            group.contains { CGRect(x: $0.minX - 2, y: $0.minY - 5, width: $0.width + 4, height: $0.height + 7).contains(point) }
        }
        if let hit, let rect = rects[hit].first {
            hideCard?.cancel()
            guard hit != hot || !card.isVisible else { return }
            hot = hit
            card.show(marks[hit], under: rect)
            overlay.show(rects: rects, keys: markKeys, hot: hot)
        } else if card.contains(point) {
            hideCard?.cancel()
        } else if card.isVisible {
            scheduleHideCard()
        }
    }

    private func scheduleHideCard() {
        hideCard?.cancel()
        hideCard = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            card.hide()
            hot = nil
            overlay.show(rects: rects, keys: markKeys, hot: nil)
        }
    }

    /// Runs one write at a time, only while the text still matches what the marks were computed from.
    /// Underlines, the dot and the hover card are hidden meanwhile.
    private func write(_ label: String, _ body: @escaping (FocusedInput) async throws -> Void) {
        guard let input = watcher.input, !isWriting else { return }
        guard input.text == markedText else { refresh(textChanged: true); return }
        isWriting = true
        card.hide()
        hot = nil
        redraw()
        Task {
            input.activate()
            _ = await input.waitUntilFocused()
            try? await Task.sleep(for: .milliseconds(50))
            do { try await body(input) } catch {
                Log.write("\(label) failed: \((error as? ClaudeError)?.logName ?? "\(error)")")
                NSSound.beep()
            }
            isWriting = false
            refresh(textChanged: true)
        }
    }

    private func apply(_ mark: Mark) {
        Log.write("apply fix range=\(mark.range.location),\(mark.range.length) kind=\(mark.kind)")
        write("apply fix") { try await $0.replace(mark.range, with: mark.fix) }
    }

    /// The marks inside `selection`, or all marks when nothing is selected.
    private func marksIn(_ selection: NSRange?) -> [Mark] {
        guard let selection else { return marks }
        return marks.filter { NSIntersectionRange($0.range, selection).length == $0.range.length }
    }

    /// Applies every underlined fix at once: no model call, no preview, as few pastes as formatting allows.
    private func acceptAllFixes(in selection: NSRange?) {
        let picked = marksIn(selection)
        guard let input = watcher.input, !picked.isEmpty else { return }
        let edits = mergedEdits(picked.map { TextEdit(range: $0.range, replacement: $0.fix) }.reversed(),
                                in: markedText, splitAt: input.formattingBoundaries())
        Log.write("accept all fixes marks=\(picked.count) writes=\(edits.count) selection=\(selection != nil)")
        celebrate()
        write("accept all") { input in
            for edit in edits { try await input.replace(edit.range, with: edit.replacement) }
        }
    }

    /// The dot opens a real macOS menu with the three actions; the result then shows in the glass popover.
    private func openPopover() {
        guard watcher.input != nil, !isWriting else { return }
        card.hide()
        if popover.isOpen { popover.close(); return }
        if menu.isOpen { menu.close(); return }
        guard connected else { popover.showNotConnected(near: icon.frame); return }
        let selection = markedSelection
        guard let input = watcher.input else { return }
        let actions: [WritingAction] = [.fixEverything, .rephrase, .shorten]
        let items = [
            ("Fix Everything", "Accept every underlined fix"),
            ("Rephrase", "Clearer, same meaning"),
            ("Make It Shorter", "Fewer words, same point"),
        ].enumerated().map { i, entry in
            LiquidMenuItem(title: entry.0, subtitle: selection == nil ? entry.1 : "\(entry.1), selected text only",
                           enabled: actions[i] != .fixEverything || !marksIn(selection).isEmpty,
                           symbol: actions[i] == .fixEverything ? "checkmark" : nil)
        }
        let color = icon.dotColor, dot = icon.dotFrame
        icon.hideForMenu()
        menu.open(items: items, dot: dot, dotColor: color, input: input.frame, onPick: { [weak self] i in
            guard let self else { return }
            let action = actions[i]
            if action == .fixEverything { self.acceptAllFixes(in: selection); return }
            self.target = selection
            let text = self.markedText as NSString
            self.popover.run(action, near: self.icon.frame, text: selection.map { text.substring(with: $0) } ?? self.markedText)
        }, onClosed: { [weak self] in self?.redraw() })
    }

    /// The happy moment for Fix Everything and Replace: underlines pull back, the dot turns green and fades.
    /// The writes run at the same time, so this never slows the fix down.
    private func celebrate() {
        celebrating = true
        overlay.retract()
        icon.celebrate()
        Task {
            try? await Task.sleep(for: .milliseconds(850))
            celebrating = false
            redraw()
        }
    }

    /// Replaces the selection (or the whole input) with a Rephrase or Shorten result, if that text is unchanged.
    private func replace(_ action: WritingAction, before: String, after: String) async {
        let range = target
        target = nil
        guard let input = watcher.input else { return }
        let current = input.text as NSString
        let unchanged = range.map { NSMaxRange($0) <= current.length && current.substring(with: $0) == before } ?? (input.text == before)
        guard unchanged else {
            popover.fail("Your text changed. Try again.")
            return
        }
        popover.closeImmediately()
        markedText = input.text
        celebrate()
        Log.write("replace \(action) selection=\(range != nil) beforeLen=\((before as NSString).length) afterLen=\((after as NSString).length)")
        write("replace") { input in
            if let range { try await input.replace(range, with: after) } else { try await input.replaceAll(with: after) }
        }
    }
}
