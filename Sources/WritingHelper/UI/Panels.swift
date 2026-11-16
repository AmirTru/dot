import AppKit

/// A floating panel that never takes focus from Slack or Zen.
class FloatingPanel: NSPanel {
    init(size: CGSize = .zero, clickThrough: Bool = false) {
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = clickThrough
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The Liquid Glass surface system popovers use, wrapping `content`.
@MainActor
func glassSurface(_ content: NSView, cornerRadius: CGFloat = 14) -> NSGlassEffectView {
    let glass = NSGlassEffectView()
    glass.cornerRadius = cornerRadius
    glass.contentView = content
    return glass
}

/// The size a glass surface needs. NSGlassEffectView reports no fitting size of its own, so measure its content.
@MainActor
func fittingSize(of glass: NSGlassEffectView) -> CGSize {
    glass.contentView?.fittingSize ?? .zero
}

/// Short, quiet motion matching system popovers. With Reduce Motion on, panels only fade.
@MainActor
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Fades the panel in while it rises 4 pt into `frame`.
    static func appear(_ panel: NSPanel, at frame: CGRect) {
        let start = reduced ? frame : frame.offsetBy(dx: 0, dy: -4)
        panel.alphaValue = 0
        panel.setFrame(start, display: true)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// Fades the panel out, then removes it unless it was shown again meanwhile.
    static func disappear(_ panel: NSPanel, isStillHidden: @escaping @MainActor () -> Bool = { true }) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { if isStillHidden() { panel.orderOut(nil) } }
        })
    }

    /// Resizes or moves a visible panel smoothly.
    static func move(_ panel: NSPanel, to frame: CGRect) {
        guard panel.isVisible, !reduced else { panel.setFrame(frame, display: true); return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }
}
