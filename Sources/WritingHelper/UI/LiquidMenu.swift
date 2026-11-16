import AppKit
import SwiftUI
import WritingCore

struct LiquidMenuItem {
    let title: String
    let subtitle: String
    let enabled: Bool
    /// An item with a symbol shows only the symbol, in a short row next to the dot, set apart by a divider.
    var symbol: String? = nil
}

/// The dot's menu. One glass shape stretches out of the dot (up, then sideways), the words fade in after it,
/// and closing pulls it back into the dot.
@MainActor
final class LiquidMenu {
    private let model = LiquidModel()
    private var panel: KeyPanel?
    private var keys: Any?
    private var outsideClick: Any?
    private var onPick: ((Int) -> Void)?
    private var onClosed: (() -> Void)?
    private(set) var isOpen = false

    static let width: CGFloat = 230
    static let rowHeight: CGFloat = 38
    static let symbolRowHeight: CGFloat = 30
    static let dividerHeight: CGFloat = 9

    func open(items: [LiquidMenuItem], dot: CGRect, dotColor: NSColor, input: CGRect,
              onPick: @escaping (Int) -> Void, onClosed: @escaping () -> Void) {
        let screen = NSScreen.screens.first { $0.frame.contains(dot.origin) }?.visibleFrame ?? .zero
        let symbols = items.filter { $0.symbol != nil }.count, texts = items.count - symbols
        let size = CGSize(width: Self.width, height: CGFloat(texts) * Self.rowHeight + CGFloat(symbols) * Self.symbolRowHeight
                          + (symbols > 0 && texts > 0 ? Self.dividerHeight : 0) + 10)
        let layout = liquidLayout(dot: dot, input: input, menuSize: size, screen: screen)
        self.onPick = onPick
        self.onClosed = onClosed
        isOpen = true

        let p = panel ?? makePanel()
        p.setFrame(layout.panel, display: false)
        model.prepare(items: items, layout: layout, color: Color(nsColor: dotColor))
        p.alphaValue = 1
        p.orderFrontRegardless()
        p.makeKey()
        startMonitors()
        if Motion.reduced {
            model.jumpOpen()
            p.alphaValue = 0
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; p.animator().alphaValue = 1 }
        } else {
            model.animateOpen()
        }
    }

    /// Closes into the dot. `then` runs once the menu is gone and has given up the keyboard,
    /// so an action that pastes into Slack or a browser lands in the right place.
    func close(then: (() -> Void)? = nil) {
        guard isOpen, let panel else { return }
        isOpen = false
        stopMonitors()
        let finish = { [weak self] in
            guard let self, !self.isOpen else { return }
            panel.orderOut(nil)
            self.onClosed?()
            then?()
        }
        if Motion.reduced {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; panel.animator().alphaValue = 0 }, completionHandler: finish)
        } else {
            model.animateClose()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.19, execute: finish)
        }
    }

    private func pick(_ index: Int) {
        guard model.items.indices.contains(index), model.items[index].enabled else { return }
        let chosen = onPick
        close { chosen?(index) }
    }

    private func makePanel() -> KeyPanel {
        let p = KeyPanel()
        p.onEscape = { [weak self] in self?.close() }
        let host = NSHostingView(rootView: LiquidMenuView(model: model, pick: { [weak self] in self?.pick($0) }))
        host.setAccessibilityRole(.menu)
        p.contentView = host
        panel = p
        return p
    }

    private func startMonitors() {
        stopMonitors()
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            let handled = MainActor.assumeIsolated { self?.handleKey(code) ?? false }
            return handled ? nil : event
        }
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func handleKey(_ code: UInt16) -> Bool {
        guard isOpen else { return false }
        // Arrow keys follow the order on screen, not the order the items were given in.
        let order = model.order
        let enabled = order.map { model.items[$0].enabled }
        let current = model.highlighted.flatMap { order.firstIndex(of: $0) }
        switch code {
        case 125: model.highlighted = nextEnabledIndex(from: current, step: 1, enabled: enabled).map { order[$0] }
        case 126: model.highlighted = nextEnabledIndex(from: current, step: -1, enabled: enabled).map { order[$0] }
        case 36, 76: if let i = model.highlighted { pick(i) }
        case 53: close()
        default: return false
        }
        return true
    }

    private func stopMonitors() {
        if let keys { NSEvent.removeMonitor(keys) }
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        keys = nil
        outsideClick = nil
    }
}

@MainActor
final class LiquidModel: ObservableObject {
    @Published var width: CGFloat = 9
    @Published var height: CGFloat = 9
    /// Moves the pinned edge from the dot to the menu's final edge: 0 at the dot, 1 open.
    @Published var lift: CGFloat = 0
    /// Moves the left edge from the dot to the menu's left, when the menu had to shift to stay on screen.
    @Published var slide: CGFloat = 0
    @Published var colorAmount: Double = 1
    @Published var content: Double = 0
    @Published var press: CGFloat = 1
    @Published var highlighted: Int?
    private(set) var items: [LiquidMenuItem] = []
    private(set) var layout = LiquidLayout(panel: .zero, dot: .zero, menu: .zero, opensUp: true)
    private(set) var color = Color.red

    /// Display order: symbol items sit next to the dot (at the bottom when the menu opens upward).
    var order: [Int] {
        let symbols = items.indices.filter { items[$0].symbol != nil }
        let texts = items.indices.filter { items[$0].symbol == nil }
        return layout.opensUp ? texts + symbols : symbols + texts
    }
    private var generation = 0

    func prepare(items: [LiquidMenuItem], layout: LiquidLayout, color: Color) {
        generation += 1
        self.items = items
        self.layout = layout
        self.color = color
        highlighted = nil
        width = layout.dot.width; height = layout.dot.height
        lift = 0; slide = 0; colorAmount = 1; content = 0; press = 0.85
    }

    func jumpOpen() {
        width = layout.menu.width; height = layout.menu.height
        lift = 1; slide = 1; colorAmount = 0; content = 1; press = 1
    }

    /// The dot already dipped on mouse-down, so the shape starts at 85% and springs back while it stretches.
    func animateOpen() {
        let g = generation
        withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) { press = 1 }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) { height = layout.menu.height; lift = 1 }
        withAnimation(.easeOut(duration: 0.13)) { colorAmount = 0 }
        after(0.03, g) { withAnimation(.spring(response: 0.27, dampingFraction: 0.66)) { self.width = self.layout.menu.width; self.slide = 1 } }
        after(0.08, g) { withAnimation(.easeOut(duration: 0.12)) { self.content = 1 } }
    }

    func animateClose() {
        generation += 1
        let g = generation
        withAnimation(.easeIn(duration: 0.05)) { content = 0 }
        after(0.03, g) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.84)) { self.width = self.layout.dot.width; self.slide = 0 }
            withAnimation(.spring(response: 0.17, dampingFraction: 0.76)) { self.height = self.layout.dot.height; self.lift = 0 }
            withAnimation(.easeIn(duration: 0.11)) { self.colorAmount = 1 }
        }
    }

    private func after(_ seconds: Double, _ g: Int, _ f: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard self?.generation == g else { return }
            f()
        }
    }

    /// The shape's frame inside the panel (SwiftUI coordinates, y down). Its pinned edge travels from
    /// the dot's edge to the menu's edge, so it visibly leaves the dot and ends clear of the text.
    var shapeFrame: CGRect {
        let p = layout.panel
        func local(_ r: CGRect) -> CGRect { CGRect(x: r.minX - p.minX, y: p.maxY - r.maxY, width: r.width, height: r.height) }
        let dot = local(layout.dot), menu = local(layout.menu)
        let x = dot.minX + (menu.minX - dot.minX) * slide
        if layout.opensUp {
            let bottom = dot.maxY + (menu.maxY - dot.maxY) * lift
            return CGRect(x: x, y: bottom - height, width: width, height: height)
        }
        let top = dot.minY + (menu.minY - dot.minY) * lift
        return CGRect(x: x, y: top, width: width, height: height)
    }
}

private struct LiquidMenuView: View {
    @ObservedObject var model: LiquidModel
    let pick: (Int) -> Void

    var body: some View {
        let frame = model.shapeFrame
        let shape = RoundedRectangle(cornerRadius: liquidCornerRadius(width: frame.width, height: frame.height), style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(model.color.opacity(model.colorAmount))
            VStack(alignment: .leading, spacing: 0) {
                let order = model.order
                ForEach(order.indices, id: \.self) { n in
                    let i = order[n]
                    if n > 0, (model.items[i].symbol == nil) != (model.items[order[n - 1]].symbol == nil) {
                        Divider().padding(.horizontal, 8).frame(height: LiquidMenu.dividerHeight)
                    }
                    if model.items[i].symbol != nil { symbolRow(i) } else { row(i) }
                }
            }
            .padding(5)
            .frame(width: model.layout.menu.width, alignment: .leading)
            .opacity(model.content)
            .blur(radius: (1 - model.content) * 4)
            .offset(y: (1 - model.content) * (model.layout.opensUp ? 4 : -4))
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .clipShape(shape)
        .glassEffect(.regular.interactive(), in: shape)
        .scaleEffect(model.press, anchor: model.layout.opensUp ? .bottomLeading : .topLeading)
        .position(x: frame.midX, y: frame.midY)
        .frame(width: model.layout.panel.width, height: model.layout.panel.height)
    }

    private func symbolRow(_ i: Int) -> some View {
        let item = model.items[i]
        let lit = model.highlighted == i && item.enabled
        return Image(systemName: item.symbol ?? "checkmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(lit ? .white : .primary)
            .opacity(item.enabled ? 1 : 0.35)
            .frame(width: LiquidMenu.width - 10, height: LiquidMenu.symbolRowHeight)
            .background(lit ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .onHover { inside in
                if inside, item.enabled { model.highlighted = i } else if model.highlighted == i { model.highlighted = nil }
            }
            .onTapGesture { pick(i) }
            .help(item.title)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.title), \(item.subtitle)")
            .accessibilityAddTraits(.isButton)
    }

    private func row(_ i: Int) -> some View {
        let item = model.items[i]
        let lit = model.highlighted == i && item.enabled
        return VStack(alignment: .leading, spacing: 1) {
            Text(item.title).font(.system(size: 13))
            Text(item.subtitle).font(.system(size: 11)).foregroundStyle(lit ? .white.opacity(0.85) : .secondary)
        }
        .foregroundStyle(lit ? .white : .primary)
        .opacity(item.enabled ? 1 : 0.4)
        .padding(.horizontal, 10)
        .frame(width: LiquidMenu.width - 10, height: 38, alignment: .leading)
        .background(lit ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onHover { inside in
            if inside, item.enabled { model.highlighted = i } else if model.highlighted == i { model.highlighted = nil }
        }
        .onTapGesture { pick(i) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(item.subtitle)")
        .accessibilityAddTraits(.isButton)
        .accessibilityRemoveTraits(item.enabled ? [] : .isButton)
    }
}
