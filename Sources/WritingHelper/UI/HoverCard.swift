import AppKit
import WritingCore

/// Small glass card under a red word: what kind of mistake, and the fix as one big button.
@MainActor
final class HoverCard {
    var onApply: ((Mark) -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    private let panel = FloatingPanel()
    private var mark: Mark?
    private(set) var isVisible = false

    func show(_ m: Mark, under rect: CGRect) {
        let wasVisible = isVisible
        mark = m
        isVisible = true
        let label = NSTextField(labelWithString: m.kind == .spelling ? "Spelling" : "Word choice")
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        let button = FixButton(title: m.fix) { [weak self] in
            guard let self, let mark = self.mark else { return }
            self.onApply?(mark)
        }
        button.onHover = { [weak self] in self?.onHoverChange?($0) }
        let stack = NSStackView(views: [label, button])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 5, bottom: 5, right: 5)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 112),
            label.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 13),
        ])
        let glass = glassSurface(stack, cornerRadius: 12)
        panel.contentView = glass
        let size = fittingSize(of: glass)
        var origin = CGPoint(x: rect.minX - 10, y: rect.minY - 6 - size.height)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(rect.origin) }) {
            if origin.y < screen.visibleFrame.minY { origin.y = rect.maxY + 6 }
            origin.x = min(max(origin.x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        }
        let frame = CGRect(origin: origin, size: size)
        if wasVisible { Motion.move(panel, to: frame); panel.alphaValue = 1 } else { Motion.appear(panel, at: frame) }
    }

    func contains(_ point: CGPoint) -> Bool { isVisible && panel.frame.insetBy(dx: -4, dy: -4).contains(point) }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        mark = nil
        Motion.disappear(panel) { [weak self] in self?.isVisible == false }
    }
}

/// The fix, styled like a macOS menu item: accent text, accent fill with white text on hover.
private final class FixButton: NSView {
    var onHover: ((Bool) -> Void)?
    private let action: () -> Void
    private let label: NSTextField
    private let fill = CALayer()

    init(title: String, action: @escaping () -> Void) {
        self.action = action
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        fill.backgroundColor = NSColor.controlAccentColor.cgColor
        fill.cornerRadius = 7
        fill.opacity = 0
        layer?.addSublayer(fill)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .controlAccentColor
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        setAccessibilityRole(.button)
        setAccessibilityLabel("Replace with \(title)")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        fill.frame = bounds
    }

    private func setHover(_ on: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        fill.opacity = on ? 1 : 0
        CATransaction.commit()
        label.textColor = on ? .white : .controlAccentColor
        onHover?(on)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { setHover(true) }
    override func mouseExited(with event: NSEvent) { setHover(false) }
    override func mouseDown(with event: NSEvent) { fill.opacity = 0.8 }
    override func mouseUp(with event: NSEvent) { action() }
}
