import AppKit
import QuartzCore
import WritingCore

/// The dot at the top-left of the focused input, shown when there are mistakes or selected text:
/// red = mistakes, accent = text selected and ready to rephrase, gray = Claude Code is not connected.
/// It is still while you type and comes alive at moments of change (docs/motion.md): it gets heavier per
/// mistake, breathes when you pause, fades gently while Haiku checks,
/// and celebrates Fix Everything.
@MainActor
final class IconPanel {
    var onClick: (() -> Void)?
    private static let side: CGFloat = 28
    private let panel = FloatingPanel(size: CGSize(width: side, height: side))
    private let view = DotView(frame: CGRect(x: 0, y: 0, width: side, height: side))
    private(set) var frame = CGRect.zero
    private var textInset: CGFloat = 12
    private var shown = false
    private var skipPop = false
    private var count = 0
    private var breathTask: Task<Void, Never>?

    var dotColor: NSColor { view.color }
    /// The visible dot, centred in the larger click area.
    var dotFrame: CGRect {
        let d = view.visibleDiameter
        return CGRect(x: frame.midX - d / 2, y: frame.midY - d / 2, width: d, height: d)
    }

    init() {
        panel.contentView = view
        view.onClick = { [weak self] in self?.onClick?() }
    }

    /// `working`: Rephrase or Make It Shorter is waiting on Claude. The dot turns the text color and thinks.
    func update(count: Int, checking: Bool, working: Bool, connected: Bool) {
        view.setWorking(working)
        view.setColor(!connected ? .systemGray : count > 0 ? .systemRed : .controlAccentColor)
        view.setDiameter(dotDiameter(mistakes: count), gulp: count > self.count && shown)
        if count == 0 { stopBreathing() }
        self.count = count
        view.setThinking(checking || working)
    }

    /// Typing stops the breathing; it starts again 1.5 s after the last key if mistakes are waiting.
    func noteTyping() {
        stopBreathing()
        breathTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self, !Task.isCancelled, self.count > 0, self.shown else { return }
            self.view.setBreathing(true)
        }
    }

    /// Fix Everything: green, one big bounce, then the dot fades away.
    func celebrate() {
        stopBreathing()
        view.celebrate { [weak self] in
            guard let self else { return }
            self.shown = false
            self.panel.orderOut(nil)
            self.view.reset()
        }
    }

    /// Always top-left, whatever the language: just left of where a left-to-right line starts,
    /// level with the first line. The gap between the input's edge and its text is learned from
    /// left-to-right text, so a Hebrew message puts the dot in the same spot.
    func pin(firstLetter: CGRect?, input: CGRect, rightToLeft: Bool) {
        if let r = firstLetter, !rightToLeft { textInset = r.minX - input.minX }
        let top = firstLetter?.maxY ?? input.maxY - 8
        let center = CGPoint(x: input.minX + textInset - 4, y: top + 2)
        frame = CGRect(x: center.x - Self.side / 2, y: center.y - Self.side / 2, width: Self.side, height: Self.side)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !shown {
            shown = true
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            if skipPop { skipPop = false } else { view.popIn() }
        }
    }

    /// Hands the dot over to the liquid menu with no fade, and brings it back later without the pop-in.
    func hideForMenu() {
        stopBreathing()
        view.setThinking(false)
        shown = false
        skipPop = true
        panel.orderOut(nil)
        view.clearHover()
    }

    func hide() {
        stopBreathing()
        view.setThinking(false)
        guard shown else { return }
        shown = false
        view.clearHover()
        Motion.disappear(panel) { [weak self] in self?.shown == false }
    }

    private func stopBreathing() {
        breathTask?.cancel()
        breathTask = nil
        view.setBreathing(false)
    }
}

/// macOS lets only the active app set the pointer, and Dot is never active. This private WindowServer
/// setting, used by many Mac utilities, lets a background app set it too. Looked up at runtime, so if a
/// future macOS removes it the pointer simply stays an arrow.
@MainActor
private let allowCursorInBackground: Void = {
    typealias MainConnection = @convention(c) () -> Int32
    typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    guard let handle = dlopen(nil, RTLD_LAZY),
          let main = dlsym(handle, "_CGSDefaultConnection"),
          let set = dlsym(handle, "CGSSetConnectionProperty") else { return }
    let cid = unsafeBitCast(main, to: MainConnection.self)()
    _ = unsafeBitCast(set, to: SetProperty.self)(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
}()

private final class DotView: NSView {
    var onClick: (() -> Void)?
    private(set) var color = NSColor.systemRed
    private(set) var diameter: CGFloat = dotDiameter(mistakes: 1)
    /// The size on screen right now, so the liquid menu starts from exactly what the person sees.
    var visibleDiameter: CGFloat { diameter * (hovering ? dotHoverScale : 1) }

    // Three nested layers, one per kind of motion, so motions stack instead of cancelling each other:
    // `holder` carries hover, `mood` carries the loops (breathing, thinking), `body` carries quick reactions.
    private let holder = CALayer()
    private let mood = CALayer()
    private let body = CALayer()
    private var thinking = false
    private var breathing = false
    private var hovering = false
    private var pressed = false
    private var working = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(holder)
        holder.frame = bounds
        holder.addSublayer(mood)
        mood.frame = bounds
        mood.addSublayer(body)
        layout(diameter: dotDiameter(mistakes: 1))
        setColor(color)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
        setAccessibilityRole(.button)
        setAccessibilityLabel("Writing help")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { press() }
    override func mouseUp(with event: NSEvent) {
        release()
        CATransaction.flush()
        onClick?()
    }
    override func mouseEntered(with event: NSEvent) {
        _ = allowCursorInBackground
        hovering = true
        NSCursor.pointingHand.set()
        settleHover()
    }
    // The app under the dot keeps resetting the cursor, so set it again on every move.
    override func mouseMoved(with event: NSEvent) { if hovering { NSCursor.pointingHand.set() } }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseExited(with event: NSEvent) {
        // Moving the panel under a still pointer can report an exit; trust where the pointer really is.
        if let window, bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) { return }
        hovering = false
        NSCursor.arrow.set()
        settleHover()
    }

    // MARK: - Motion building blocks

    /// Moves a property to `to` with a spring that starts from what is on screen now, so a new target
    /// redirects the motion mid-flight instead of restarting it.
    private func springTo(_ layer: CALayer, _ keyPath: String, _ to: CGFloat, duration: Double, bounce: Double) {
        let from = (layer.presentation() ?? layer).value(forKeyPath: keyPath) as? CGFloat ?? to
        layer.setValue(to, forKeyPath: keyPath)
        guard !Motion.reduced else { return }
        let anim = CASpringAnimation(perceptualDuration: duration, bounce: bounce)
        anim.keyPath = keyPath
        anim.fromValue = from
        anim.toValue = to
        layer.add(anim, forKey: keyPath)
    }

    /// A quick squash or pop on top of whatever else the dot is doing. Impulses are additive:
    /// two that overlap blend together instead of the second cutting off the first.
    private func impulse(scaleX: CGFloat, scaleY: CGFloat, duration: Double, bounce: Double) {
        guard !Motion.reduced else { return }
        for (path, s) in [("transform.scale.x", scaleX), ("transform.scale.y", scaleY)] where s != 1 {
            let anim = CASpringAnimation(perceptualDuration: duration, bounce: bounce)
            anim.keyPath = path
            anim.fromValue = s - 1
            anim.toValue = 0
            anim.isAdditive = true
            body.add(anim, forKey: nil)
        }
    }

    /// Ends a loop by easing from where it is on screen back to rest, instead of snapping.
    private func endLoop(_ key: String) {
        guard mood.animation(forKey: key) != nil else { return }
        let p = mood.presentation()
        let scale = p?.value(forKeyPath: "transform.scale") as? CGFloat ?? 1
        let opacity = p?.opacity ?? 1
        mood.removeAnimation(forKey: key)
        guard !Motion.reduced else { return }
        let back = CASpringAnimation(perceptualDuration: 0.3, bounce: 0.1)
        back.keyPath = "transform.scale"
        back.fromValue = scale
        back.toValue = 1
        mood.add(back, forKey: "ease-scale")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity
        fade.toValue = 1
        fade.duration = 0.2
        mood.add(fade, forKey: "ease-opacity")
    }

    /// Starts a loop from the current on-screen state: a short ease into its first value, then the loop.
    private func startLoop(_ key: String, scaleTo: CGFloat, opacityTo: Float, half: Double, timing: CAMediaTimingFunctionName) {
        guard !Motion.reduced else { return }
        let p = mood.presentation()
        let scale = p?.value(forKeyPath: "transform.scale") as? CGFloat ?? 1
        let opacity = p?.opacity ?? 1
        mood.removeAnimation(forKey: "ease-scale")
        mood.removeAnimation(forKey: "ease-opacity")
        let s = CAKeyframeAnimation(keyPath: "transform.scale")
        s.values = [scale, 1, scaleTo, 1]
        let o = CAKeyframeAnimation(keyPath: "opacity")
        o.values = [opacity, 1, opacityTo, 1]
        let lead = 0.12
        let total = lead + 2 * half
        let times: [NSNumber] = [0, NSNumber(value: lead / total), NSNumber(value: (lead + half) / total), 1]
        s.keyTimes = times
        o.keyTimes = times
        let intro = CAAnimationGroup()
        intro.animations = [s, o]
        intro.duration = total
        intro.timingFunction = CAMediaTimingFunction(name: timing)
        let loopS = CABasicAnimation(keyPath: "transform.scale")
        loopS.fromValue = 1
        loopS.toValue = scaleTo
        let loopO = CABasicAnimation(keyPath: "opacity")
        loopO.fromValue = 1
        loopO.toValue = opacityTo
        let loop = CAAnimationGroup()
        loop.animations = [loopS, loopO]
        loop.duration = half
        loop.autoreverses = true
        loop.repeatCount = .infinity
        loop.timingFunction = CAMediaTimingFunction(name: timing)
        loop.beginTime = CACurrentMediaTime() + total
        loop.fillMode = .backwards
        mood.add(intro, forKey: key + "-intro")
        mood.add(loop, forKey: key)
    }

    // MARK: - States

    /// The dot is drawn as a border as thick as its radius, so on hover its fill can drain into a thin ring.
    func setColor(_ new: NSColor) {
        color = new
        paint()
    }

    /// On hover the ring takes the text color (white in dark mode, black in light mode): it says
    /// "you're pointing at it" without looking like red, blue or gray, which each mean a state.
    private func paint() {
        let neutral = (hovering && !pressed) || working
        var cg = color.cgColor
        if neutral { effectiveAppearance.performAsCurrentDrawingAppearance { cg = NSColor.labelColor.cgColor } }
        guard body.borderColor != cg else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(Motion.reduced ? 0 : 0.2)
        body.borderColor = cg
        CATransaction.commit()
    }

    /// One point heavier per mistake; a new mistake makes it gulp (a quick squash) before it settles.
    func setDiameter(_ d: CGFloat, gulp: Bool) {
        if d != diameter {
            diameter = d
            CATransaction.begin()
            CATransaction.setAnimationDuration(Motion.reduced ? 0 : 0.2)
            layout(diameter: d)
            CATransaction.commit()
        }
        if gulp { impulse(scaleX: 1.18, scaleY: 0.82, duration: 0.35, bounce: 0.25) }
    }

    func setWorking(_ on: Bool) {
        guard on != working else { return }
        working = on
        paint()
    }

    /// While Haiku checks, the dot fades and shrinks gently, twice a second; when the answer lands it settles.
    func setThinking(_ on: Bool) {
        guard on != thinking else { return }
        thinking = on
        if Motion.reduced {
            mood.opacity = on ? 0.5 : 1
            return
        }
        if on {
            // Read where breathing has the dot before removing it, so thinking takes over from there.
            startLoop("thinking", scaleTo: 0.8, opacityTo: 0.35, half: 0.5, timing: .easeInEaseOut)
            mood.removeAnimation(forKey: "breath")
            mood.removeAnimation(forKey: "breath-intro")
        } else {
            mood.removeAnimation(forKey: "thinking-intro")
            endLoop("thinking")
            impulse(scaleX: 0.9, scaleY: 1.1, duration: 0.3, bounce: 0.2)
            if breathing { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.resumeBreathing() } }
        }
    }

    /// About 4% bigger and back, one breath every ~4 s, each breath a little different.
    func setBreathing(_ on: Bool) {
        guard on != breathing else { return }
        breathing = on
        if on { resumeBreathing() } else {
            mood.removeAnimation(forKey: "breath-intro")
            endLoop("breath")
        }
    }

    private func resumeBreathing() {
        guard breathing, !thinking, !Motion.reduced else { return }
        startLoop("breath", scaleTo: 1.04, opacityTo: 1, half: breathingPeriod(random: .random(in: 0...1)) / 2, timing: .easeInEaseOut)
    }

    func celebrate(done: @escaping () -> Void) {
        setBreathing(false)
        setThinking(false)
        setColor(.systemGreen)
        ripple(scale: 2.6, duration: 0.5)
        springTo(body, "transform.scale", 1.25, duration: 0.45, bounce: 0.3)
        impulse(scaleX: 1.2, scaleY: 0.72, duration: 0.45, bounce: 0.3)
        CATransaction.begin()
        CATransaction.setCompletionBlock(done)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.beginTime = CACurrentMediaTime() + 0.55
        fade.duration = 0.25
        fade.fillMode = .both
        fade.isRemovedOnCompletion = false
        layer?.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    func reset() {
        body.removeAllAnimations()
        mood.removeAllAnimations()
        layer?.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body.transform = CATransform3DIdentity
        mood.transform = CATransform3DIdentity
        mood.opacity = 1
        CATransaction.commit()
        setColor(.systemRed)
    }

    /// A hidden dot can't know where the pointer went, so it comes back at rest size.
    func clearHover() {
        hovering = false
        pressed = false
        holder.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        holder.transform = CATransform3DIdentity
        body.transform = CATransform3DIdentity
        body.borderWidth = diameter / 2
        body.borderColor = color.cgColor
        CATransaction.commit()
    }

    // MARK: - Clicks and hover

    /// Click feedback: the ring fills back in and the dot dips to 80%; on release it springs back
    /// from wherever the dip got to, while a faint ring ripples out.
    private func press() {
        pressed = true
        paint()
        setFill(full: true, duration: 0.08)
        springTo(body, "transform.scale", 0.8, duration: 0.12, bounce: 0)
    }

    private func release() {
        pressed = false
        paint()
        springTo(body, "transform.scale", 1, duration: 0.3, bounce: 0.2)
        ripple(scale: 1.7, duration: 0.32)
        setFill(full: !hovering, duration: 0.25)
    }

    private func settleHover() {
        springTo(holder, "transform.scale", hovering ? dotHoverScale : 1, duration: 0.25, bounce: 0.15)
        if !pressed { setFill(full: !hovering, duration: 0.25) }
        paint()
    }

    private func ripple(scale: CGFloat, duration: CFTimeInterval) {
        guard !Motion.reduced else { return }
        let ring = CAShapeLayer()
        let r = diameter / 2
        ring.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        ring.position = CGPoint(x: bounds.midX, y: bounds.midY)
        ring.fillColor = nil
        ring.strokeColor = color.cgColor
        ring.lineWidth = 1.5
        ring.opacity = 0
        holder.addSublayer(ring)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = scale
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.6
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(group, forKey: "ripple")
        CATransaction.commit()
    }

    /// A small spring from 40% to full size, like a system badge appearing. Additive, so it blends with
    /// anything already playing.
    func popIn() {
        impulse(scaleX: 0.4, scaleY: 0.4, duration: 0.35, bounce: 0.2)
    }

    // MARK: - Geometry

    private func layout(diameter d: CGFloat) {
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        body.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        body.position = c
        body.cornerRadius = d / 2
        body.borderWidth = hovering && !pressed ? ringWidth : d / 2
    }

    /// About 1 pt on screen once the hover scale is applied.
    private var ringWidth: CGFloat { 1 / dotHoverScale }

    private func setFill(full: Bool, duration: CFTimeInterval) {
        let to = full ? diameter / 2 : ringWidth
        let from = body.presentation()?.borderWidth ?? body.borderWidth
        body.borderWidth = to
        guard !Motion.reduced else { return }
        let anim = CABasicAnimation(keyPath: "borderWidth")
        anim.fromValue = from
        anim.toValue = to
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        body.add(anim, forKey: "fill")
    }
}
