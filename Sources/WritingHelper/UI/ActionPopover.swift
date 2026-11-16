import AppKit
import SwiftUI
import WritingCore

/// The popover behind the round icon. It takes keyboard focus because opening it is a deliberate click.
@MainActor
final class ActionPopover {
    var onRun: ((WritingAction, String) async throws -> String)?
    var onReplace: ((WritingAction, String, String) async -> Void)?
    var onConnect: (() -> Void)?
    var onClose: (() -> Void)?

    private let model = PopoverModel()
    private var panel: KeyPanel?
    private var outsideClick: Any?
    private var anchor = CGRect.zero
    private var text = ""
    private var runTask: Task<Void, Never>?
    var isOpen: Bool { panel?.isVisible ?? false }

    init() {
        model.run = { [weak self] in self?.run($0) }
        model.replace = { [weak self] action, before, after in
            guard let self else { return }
            Task { await self.onReplace?(action, before, after) }
        }
        model.connect = { [weak self] in
            self?.model.screen = .connecting
            self?.onConnect?()
        }
        model.close = { [weak self] in self?.close() }
    }

    /// Runs an action picked from the menu, showing progress and then the result.
    func run(_ action: WritingAction, near icon: CGRect, text: String) {
        open(near: icon, text: text)
        run(action)
    }

    /// Explains that Claude Code is not connected, with a Connect button.
    func showNotConnected(near icon: CGRect) {
        open(near: icon, text: "")
        model.screen = .notConnected
    }

    private func open(near icon: CGRect, text: String) {
        anchor = icon
        self.text = text
        let wasOpen = panel?.isVisible == true
        if panel == nil {
            let p = KeyPanel()
            let host = NSHostingView(rootView: PopoverView(model: model))
            host.sizingOptions = [.intrinsicContentSize]
            p.contentView = glassSurface(host, cornerRadius: 16)
            p.onEscape = { [weak self] in self?.close() }
            panel = p
            model.resize = { [weak self] in self?.place(animated: true) }
        }
        if wasOpen { place(animated: true) } else if let panel { Motion.appear(panel, at: targetFrame()) }
        panel?.makeKey()
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func connected() {
        if model.screen == .connecting || model.screen == .notConnected { close() }
    }

    func fail(_ message: String) { model.screen = .failed(message) }

    /// Removes the popover at once so it gives up the keyboard before the app pastes into Slack or Zen.
    func closeImmediately() {
        runTask?.cancel()
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        outsideClick = nil
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        onClose?()
    }

    func close() {
        runTask?.cancel()
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        outsideClick = nil
        guard let panel, panel.isVisible, panel.alphaValue > 0 else { return }
        Motion.disappear(panel) { [weak self] in self?.outsideClick == nil }
        onClose?()
    }

    private func run(_ action: WritingAction) {
        model.screen = .busy(action)
        let before = text
        let start = ContinuousClock.now
        runTask = Task {
            do {
                let after = try await onRun?(action, before) ?? before
                guard !Task.isCancelled else { return }
                let elapsed = (ContinuousClock.now - start).components
                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                model.screen = .result(action, before: before, after: after, seconds: seconds)
            } catch {
                guard !Task.isCancelled else { return }
                model.screen = .failed("Haiku didn't answer. Try again.")
            }
        }
    }

    private func targetFrame() -> CGRect {
        guard let glass = panel?.contentView as? NSGlassEffectView else { return .zero }
        let size = fittingSize(of: glass)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) }?.visibleFrame ?? .zero
        var origin = CGPoint(x: anchor.minX - 4, y: anchor.maxY + 6)
        if origin.y + size.height > screen.maxY - 8 { origin.y = anchor.minY - 6 - size.height }
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
        return CGRect(origin: origin, size: size)
    }

    private func place(animated: Bool) {
        guard let panel else { return }
        if animated { Motion.move(panel, to: targetFrame()) } else { panel.setFrame(targetFrame(), display: true) }
    }
}

final class KeyPanel: NSPanel {
    var onEscape: (() -> Void)?
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor
final class PopoverModel: ObservableObject {
    enum Screen: Equatable {
        case notConnected, connecting
        case busy(WritingAction)
        case result(WritingAction, before: String, after: String, seconds: Double)
        case failed(String)
    }
    @Published var screen: Screen = .connecting { didSet { DispatchQueue.main.async { self.resize?() } } }
    var run: ((WritingAction) -> Void)?
    var replace: ((WritingAction, String, String) -> Void)?
    var connect: (() -> Void)?
    var close: (() -> Void)?
    var resize: (() -> Void)?
}

private func busyText(_ a: WritingAction) -> String {
    switch a {
    case .fixEverything: "Fixing with Haiku…"
    case .rephrase: "Rephrasing with Haiku…"
    case .shorten: "Shortening with Haiku…"
    }
}

private struct PopoverView: View {
    @ObservedObject var model: PopoverModel
    @FocusState private var focused: Bool

    var body: some View {
        content
            .frame(width: 300, alignment: .leading)
            .padding(6)
            .animation(Motion.reduced ? nil : .snappy(duration: 0.2), value: model.screen)
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onAppear { focused = true }
    }

    @ViewBuilder private var content: some View {
        switch model.screen {
        case .busy(let action):
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(busyText(action)).foregroundStyle(.secondary) }
                .padding(12).transition(.opacity)
        case .result(let action, let before, let after, let seconds):
            VStack(alignment: .leading, spacing: 10) {
                Text(after)
                    .font(.body).lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                HStack(spacing: 8) {
                    Text(String(format: "Haiku · %.1f s", seconds)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Button("Cancel") { model.close?() }.keyboardShortcut(.cancelAction)
                    Button("Replace") { model.replace?(action, before, after) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.regular)
            }
            .padding(6)
            .transition(.opacity)
        case .notConnected:
            message("Your Anthropic account isn't connected", "Red underlines still work. Rephrase and Make It Shorter need your Anthropic account.") {
                Button("Not now") { model.close?() }
                Button("Connect Anthropic Account") { model.connect?() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        case .connecting:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Finish logging in in Terminal…").foregroundStyle(.secondary) }
                .padding(12).transition(.opacity)
        case .failed(let text):
            message(text, nil) { Button("OK") { model.close?() }.keyboardShortcut(.defaultAction) }
        }
    }

    private func message(_ title: String, _ body: String?, @ViewBuilder buttons: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if let body { Text(body).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 8) { Spacer(); buttons() }.padding(.top, 4)
        }
        .padding(10)
        .transition(.opacity)
    }
}
