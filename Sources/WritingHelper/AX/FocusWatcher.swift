import AppKit
import ApplicationServices
import Carbon
import WritingCore

/// Follows the focused text input in Slack or a browser. AX notifications give instant updates;
/// a 250 ms poll catches what Electron and Firefox don't report (scrolling, missed edits).
@MainActor
final class FocusWatcher {
    var onFocus: ((FocusedInput?) -> Void)?
    var onTextChange: (() -> Void)?
    var onCaretChange: (() -> Void)?
    var onGeometryWillChange: (() -> Void)?
    var onGeometryChange: (() -> Void)?
    /// Every poll, so the controller can notice scrolling inside the input.
    var onTick: (() -> Void)?
    var onSlackNeedsRestart: ((Bool) -> Void)?

    private(set) var input: FocusedInput?
    /// The site of the focused browser page, for the menu's "Don't Check on" item.
    private(set) var currentSite: String?
    private var observer: AXObserver?
    private var observedApp: pid_t = 0
    private var lastText = ""
    private var lastSelection: NSRange?
    private var lastFrame = CGRect.zero
    private var settleTask: Task<Void, Never>?
    private var poll: Timer?
    private var lastLogged: AXUIElement?

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.appChanged() }
        }
        poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
        appChanged()
    }

    /// Applies a change to the blocked lists right away.
    func recheck() {
        stopObserving()
        appChanged()
    }

    private func appChanged() {
        guard let app = NSWorkspace.shared.frontmostApplication, !isBlockedApp(app.bundleIdentifier, blocked: Settings.blockedApps) else {
            currentSite = nil
            stopObserving()
            setInput(nil)
            return
        }
        let target = appFamily(bundleID: app.bundleIdentifier)
        if target == .slack { onSlackNeedsRestart?(!Slack.slackHasAccessibility(app)) }
        guard app.processIdentifier != observedApp else { refreshFocus(); return }
        stopObserving()
        observedApp = app.processIdentifier
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        // Chromium and Electron apps build their accessibility tree only when asked; other apps ignore this.
        AX.set(appElement, "AXManualAccessibility", kCFBooleanTrue)
        // Chrome itself ignores that and reports zero-size text positions until VoiceOver's switch is on.
        // Only Chromium browsers get it: in other apps it can slow window animations.
        if target == .chromium { AX.set(appElement, "AXEnhancedUserInterface", kCFBooleanTrue) }
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<FocusWatcher>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            MainActor.assumeIsolated { watcher.handle(name) }
        }
        guard AXObserverCreate(app.processIdentifier, callback, &obs) == .success, let obs else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification, kAXValueChangedNotification,
                  kAXSelectedTextChangedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification] {
            AXObserverAddNotification(obs, appElement, n as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        refreshFocus()
    }

    private func stopObserving() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        observedApp = 0
    }

    private func handle(_ notification: String) {
        switch notification {
        case kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification:
            refreshFocus()
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            onGeometryWillChange?()
            settleTask?.cancel()
            settleTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                self.onGeometryChange?()
            }
        default:
            tick()
        }
    }

    private func refreshFocus() {
        guard let app = NSWorkspace.shared.frontmostApplication, !isBlockedApp(app.bundleIdentifier, blocked: Settings.blockedApps),
              let focused = AX.attr(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedUIElementAttribute) else {
            setInput(nil)
            return
        }
        let element = focused as! AXUIElement
        let role = AX.attr(element, kAXRoleAttribute) as? String ?? ""
        let subrole = AX.attr(element, kAXSubroleAttribute) as? String
        let editable = AX.attr(element, "AXEditable") as? Bool ?? false
        let size = AX.attr(element, kAXSizeAttribute).flatMap { v -> CGSize? in
            var s = CGSize.zero
            return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
        }
        guard isEligibleInput(role: role, subrole: subrole, editable: editable, secureInput: IsSecureEventInputEnabled(), size: size) else { setInput(nil); return }
        let target = appFamily(bundleID: app.bundleIdentifier)
        if target.isBrowser {
            // A browser's own address bar has no page above it: searches aren't messages.
            let url = pageURL(of: element)
            currentSite = site(of: url)
            let blocked = url == nil || isBlockedSite(url, blocked: Settings.blockedSites)
            if lastLogged.map({ !CFEqual($0, element) }) ?? true {
                lastLogged = element
                Log.write("focus \(target) role=\(role) page=\(url == nil ? "none" : "found") blocked=\(blocked)")
            }
            if blocked { setInput(nil); return }
        } else {
            currentSite = nil
        }
        if let input, CFEqual(input.element, element) { return }
        setInput(FocusedInput(element: element, app: app, target: target))
    }

    /// The address of the page that holds this element, from the nearest web area above it.
    private func pageURL(of element: AXUIElement) -> String? {
        var current: AXUIElement? = element
        for _ in 0..<40 {
            guard let el = current else { return nil }
            if AX.attr(el, kAXRoleAttribute) as? String == "AXWebArea", let url = AX.attr(el, kAXURLAttribute) {
                return (url as? URL)?.absoluteString ?? url as? String
            }
            current = AX.attr(el, kAXParentAttribute).map { $0 as! AXUIElement }
        }
        return nil
    }

    private func setInput(_ new: FocusedInput?) {
        if input == nil && new == nil { return }
        input = new
        lastText = new?.text ?? ""
        lastSelection = new?.selectedRange
        lastFrame = new?.frame ?? .zero
        onFocus?(new)
    }

    private func tick() {
        guard let input else { if observer != nil { refreshFocus() }; return }
        // A page can turn a text field into a password field without moving focus.
        if IsSecureEventInputEnabled() || AX.attr(input.element, kAXSubroleAttribute) as? String == "AXSecureTextField" {
            setInput(nil)
            return
        }
        let text = input.text, selection = input.selectedRange, frame = input.frame
        if text != lastText { lastText = text; lastSelection = selection; onTextChange?() }
        else if selection != lastSelection { lastSelection = selection; onCaretChange?() }
        if frame != lastFrame { lastFrame = frame; onGeometryChange?() } else { onTick?() }
    }
}
