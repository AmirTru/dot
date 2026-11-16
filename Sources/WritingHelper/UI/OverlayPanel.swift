import AppKit
import QuartzCore

/// Click-through layer that draws the red underlines. Each underline is its own layer, so a new
/// mistake fades in while existing ones stay still.
@MainActor
final class OverlayPanel {
    private let panel = FloatingPanel(clickThrough: true)
    private let view = NSView()
    private var lines: [String: CALayer] = [:]
    private var highlights: [String: CALayer] = [:]

    init() {
        view.wantsLayer = true
        panel.contentView = view
    }

    /// `keys` identify each mark across redraws (same word, same fix → same layer).
    func show(rects: [[CGRect]], keys: [String], hot: Int?) {
        let screens = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        if panel.frame != screens { panel.setFrame(screens, display: false) }
        if !panel.isVisible { panel.orderFrontRegardless() }
        let origin = screens.origin
        var seen = Set<String>()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, group) in rects.enumerated() {
            guard let r = group.first, i < keys.count else { continue }
            let key = keys[i]
            seen.insert(key)
            let local = r.offsetBy(dx: -origin.x, dy: -origin.y)
            let line = lines[key] ?? makeLine(key)
            line.frame = CGRect(x: local.minX, y: local.minY - 2, width: local.width, height: 2)
            let glow = highlights[key] ?? makeHighlight(key)
            glow.frame = local.insetBy(dx: -2, dy: -1)
            fade(glow, to: i == hot ? 1 : 0, duration: 0.12)
        }
        CATransaction.commit()
        for (key, layer) in lines where !seen.contains(key) {
            lines[key] = nil
            remove(layer)
            if let glow = highlights.removeValue(forKey: key) { remove(glow) }
        }
    }

    func hide() {
        for layer in lines.values { layer.removeFromSuperlayer() }
        for layer in highlights.values { layer.removeFromSuperlayer() }
        lines = [:]
        highlights = [:]
    }

    private func makeLine(_ key: String) -> CALayer {
        let layer = CALayer()
        layer.backgroundColor = NSColor.systemRed.cgColor
        layer.cornerRadius = 1
        layer.opacity = 0
        view.layer?.addSublayer(layer)
        lines[key] = layer
        fade(layer, to: 1, duration: 0.15)
        return layer
    }

    private func makeHighlight(_ key: String) -> CALayer {
        let layer = CALayer()
        layer.backgroundColor = NSColor.systemRed.withAlphaComponent(0.14).cgColor
        layer.cornerRadius = 4
        layer.opacity = 0
        view.layer?.insertSublayer(layer, at: 0)
        highlights[key] = layer
        return layer
    }

    private func fade(_ layer: CALayer, to opacity: Float, duration: CFTimeInterval) {
        guard layer.opacity != opacity else { return }
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = layer.presentation()?.opacity ?? layer.opacity
        anim.toValue = opacity
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.opacity = opacity
        layer.add(anim, forKey: "fade")
    }

    /// Fix Everything: each underline pulls back toward the dot (its left end), one after another, then is gone.
    func retract() {
        let all = lines.values.sorted { $0.frame.minX < $1.frame.minX }
        for glow in highlights.values { glow.removeFromSuperlayer() }
        lines = [:]
        highlights = [:]
        for (i, line) in all.enumerated() {
            let frame = line.frame
            line.anchorPoint = CGPoint(x: 0, y: 0.5)
            line.position = CGPoint(x: frame.minX, y: frame.midY)
            let shrink = CABasicAnimation(keyPath: "transform.scale.x")
            shrink.fromValue = 1
            shrink.toValue = 0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [shrink, fade]
            group.beginTime = CACurrentMediaTime() + Double(i) * 0.05
            group.duration = Motion.reduced ? 0.12 : 0.22
            group.timingFunction = CAMediaTimingFunction(name: .easeIn)
            group.fillMode = .both
            group.isRemovedOnCompletion = false
            CATransaction.begin()
            CATransaction.setCompletionBlock { line.removeFromSuperlayer() }
            line.add(group, forKey: "retract")
            CATransaction.commit()
        }
    }

    private func remove(_ layer: CALayer) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        fade(layer, to: 0, duration: 0.1)
        CATransaction.commit()
    }
}
