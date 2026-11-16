import AppKit

/// Shown when Slack runs without accessibility turned on: one click restarts it with the flag.
@MainActor
final class SlackBanner {
    private let panel = FloatingPanel()
    private var dismissedFor: Set<pid_t> = []

    func update(needsRestart: Bool) {
        guard needsRestart, let app = NSWorkspace.shared.frontmostApplication, !dismissedFor.contains(app.processIdentifier) else {
            panel.orderOut(nil)
            return
        }
        let pid = app.processIdentifier
        let text = NSTextField(wrappingLabelWithString: "Dot can't see Slack yet. Restart Slack to turn on checking. An unsent message stays saved as a draft.")
        text.font = .systemFont(ofSize: NSFont.systemFontSize)
        text.preferredMaxLayoutWidth = 300
        let restart = ClickButton(title: "Restart Slack") { [weak self] in
            if let panel = self?.panel { Motion.disappear(panel) }
            Slack.restartSlackWithAccessibility()
        }
        restart.keyEquivalent = "\r"
        let later = ClickButton(title: "Not now") { [weak self] in
            self?.dismissedFor.insert(pid)
            if let panel = self?.panel { Motion.disappear(panel) }
        }
        let buttons = NSStackView(views: [later, restart])
        let stack = NSStackView(views: [text, buttons])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let glass = glassSurface(stack, cornerRadius: 16)
        panel.contentView = glass
        let size = fittingSize(of: glass)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let frame = CGRect(x: screen.maxX - size.width - 16, y: screen.maxY - size.height - 12, width: size.width, height: size.height)
        if panel.isVisible { panel.setFrame(frame, display: true) } else { Motion.appear(panel, at: frame) }
    }
}

final class ClickButton: NSButton {
    private var handler: (() -> Void)?
    convenience init(title: String, handler: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title
        bezelStyle = .push
        self.handler = handler
        target = self
        action = #selector(fire)
    }
    @objc private func fire() { handler?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
