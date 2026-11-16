import AppKit
import ApplicationServices
import WritingCore

enum WriteError: Error { case selectionDidNotMove, writeRejected, lostFocus }

@MainActor
final class FocusedInput {
    let element: AXUIElement
    let app: NSRunningApplication
    let target: AppFamily

    init(element: AXUIElement, app: NSRunningApplication, target: AppFamily) {
        self.element = element; self.app = app; self.target = target
        AXUIElementSetMessagingTimeout(element, 0.25)
    }

    var text: String { AX.attr(element, kAXValueAttribute) as? String ?? "" }

    var caret: Int? {
        guard let r = AX.range(AX.attr(element, kAXSelectedTextRangeAttribute)) else { return nil }
        return r.location + r.length
    }

    var selectedRange: NSRange? { AX.range(AX.attr(element, kAXSelectedTextRangeAttribute)) }

    /// AppKit coordinates.
    var frame: CGRect {
        guard let p = AX.point(AX.attr(element, kAXPositionAttribute)), let s = AX.size(AX.attr(element, kAXSizeAttribute)) else { return .zero }
        return axRectToAppKit(CGRect(origin: p, size: s), primaryScreenHeight: Self.primaryHeight)
    }

    /// AppKit rects under the given text ranges; empty for a range whose position is unknown or scrolled out of view.
    func rects(for ranges: [NSRange]) -> [[CGRect]] {
        let visible = frame.insetBy(dx: -2, dy: -2)
        return unclippedRects(for: ranges).map { $0.filter { visible.contains(CGPoint(x: $0.midX, y: $0.midY)) } }
    }

    /// Where formatting runs start in a rich-text input (its static-text pieces); empty for a plain textarea.
    func formattingBoundaries() -> Set<Int> {
        let values = staticTextNodes(element, depth: 0).map { AX.attr($0, kAXValueAttribute) as? String ?? "" }
        return Set(pieceOffsets(values, in: text).compactMap { $0 })
    }

    /// Plain inputs answer bounds queries themselves. Rich-text inputs in Slack and Chromium pages answer
    /// only on their static-text pieces, so a range is first located inside its piece.
    private func unclippedRects(for ranges: [NSRange]) -> [[CGRect]] {
        if target != .slack {
            let direct = ranges.map { r -> [CGRect] in
                guard let rect = AX.rect(AX.param(element, kAXBoundsForRangeParameterizedAttribute, AX.value(r))), rect.width > 0 else { return [] }
                return [axRectToAppKit(rect, primaryScreenHeight: Self.primaryHeight)]
            }
            if ranges.isEmpty || direct.contains(where: { !$0.isEmpty }) { return direct }
        }
        let nodes = staticTextNodes(element, depth: 0)
        let values = nodes.map { AX.attr($0, kAXValueAttribute) as? String ?? "" }
        let offsets = pieceOffsets(values, in: text)
        var pieces: [NSRange] = []
        var pieceNodes: [AXUIElement] = []
        for (i, offset) in offsets.enumerated() {
            guard let offset else { continue }
            pieces.append(NSRange(location: offset, length: (values[i] as NSString).length))
            pieceNodes.append(nodes[i])
        }
        return ranges.map { r in
            guard let hit = locate(r, pieces: pieces),
                  let rect = AX.rect(AX.param(pieceNodes[hit.index], kAXBoundsForRangeParameterizedAttribute, AX.value(hit.local))),
                  rect.width > 0 else { return [] }
            return [axRectToAppKit(rect, primaryScreenHeight: Self.primaryHeight)]
        }
    }

    func replace(_ range: NSRange, with replacement: String) async throws {
        let caretBefore = caret
        try await write(replacement, over: range)
        if let caretBefore {
            let delta = (replacement as NSString).length - range.length
            let newCaret = caretBefore > NSMaxRange(range) ? caretBefore + delta : range.location + (replacement as NSString).length
            AX.set(element, kAXSelectedTextRangeAttribute, AX.value(NSRange(location: newCaret, length: 0)))
        }
    }

    func replaceAll(with replacement: String) async throws {
        try await write(replacement, over: NSRange(location: 0, length: (text as NSString).length))
    }

    /// Brings the app back to the front. Never sets AXFocused: Slack and Zen select all text when focused that way.
    func activate() {
        app.activate()
    }

    private func write(_ replacement: String, over range: NSRange) async throws {
        let before = text
        let lengthBefore = (before as NSString).length
        AX.set(element, kAXSelectedTextRangeAttribute, AX.value(range))
        defer {
            Log.write("write \(target) range=\(range.location),\(range.length) newLen=\((replacement as NSString).length) textLen \(lengthBefore)->\((text as NSString).length)")
        }
        guard await waitUntil(timeout: .milliseconds(400), { AX.range(AX.attr(element, kAXSelectedTextRangeAttribute)) == range }) else {
            throw WriteError.selectionDidNotMove
        }
        guard isFocusedTarget() else { throw WriteError.lostFocus }
        guard await Self.paste(replacement, stillTarget: isFocusedTarget, landed: { self.text != before }) else { throw WriteError.lostFocus }
        guard text != before else { throw WriteError.writeRejected }
    }

    /// Waits until this input's app is frontmost and this exact input has keyboard focus again.
    func waitUntilFocused() async -> Bool {
        await waitUntil(timeout: .milliseconds(800)) { isFocusedTarget() }
    }

    /// True only when a paste would land in this input: its app is frontmost, none of our windows holds
    /// the keyboard, and the app's focused element is this element.
    func isFocusedTarget() -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier, NSApp.keyWindow == nil,
              let focused = AX.attr(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedUIElementAttribute)
        else { return false }
        return CFEqual(focused, element)
    }

    /// Slack and Zen ignore or misplace AXSelectedText writes, so paste over the selection, then put the
    /// clipboard back once the text has changed. Returns false when focus moved away just before the keystroke.
    private static func paste(_ s: String, stillTarget: () -> Bool, landed: () -> Bool) async -> Bool {
        let board = NSPasteboard.general
        let saved = board.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { $0[$1] = item.data(forType: $1) }
        } ?? []
        let restorable = shouldRestoreClipboard(types: saved.flatMap { $0.keys.map(\.rawValue) })
        board.clearContents()
        let temporary = NSPasteboardItem()
        temporary.setString(s, forType: .string)
        temporary.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        temporary.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))
        board.writeObjects([temporary])
        let ours = board.changeCount
        let restore = {
            guard board.changeCount == ours else { return }
            board.clearContents()
            guard restorable else { return }
            board.writeObjects(saved.map { types in
                let item = NSPasteboardItem()
                types.forEach { item.setData($0.value, forType: $0.key) }
                return item
            })
        }
        guard stillTarget() else { restore(); return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        guard await waitUntil(timeout: .seconds(2), landed) else {
            // A slow app may still paste later. Restoring now could make it paste the old clipboard over the text.
            Log.write("paste not confirmed, clipboard restored in 10 s")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                restore()
            }
            return true
        }
        try? await Task.sleep(for: .milliseconds(30))
        restore()
        return true
    }

    private func staticTextNodes(_ el: AXUIElement, depth: Int) -> [AXUIElement] {
        if AX.attr(el, kAXRoleAttribute) as? String == "AXStaticText" { return [el] }
        guard depth < 8 else { return [] }
        return ((AX.attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []).flatMap { staticTextNodes($0, depth: depth + 1) }
    }

    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }
}
