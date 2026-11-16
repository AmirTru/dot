import AppKit
import Combine
import ServiceManagement
import WritingCore

@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let auth: AuthMonitor
    private var subscription: AnyCancellable?
    private let menu = NSMenu()
    var needsAccessibility = false
    var slackNeedsRestart = false
    var onSetup: (() -> Void)?
    var onSites: (() -> Void)?
    var currentSite: (() -> String?)?
    var onBlockChanged: (() -> Void)?

    init(auth: AuthMonitor) {
        self.auth = auth
        super.init()
        menu.delegate = self
        item.menu = menu
        subscription = auth.$state.sink { [weak self] state in
            self?.item.button?.image = Self.icon(connected: state != .disconnected)
        }
    }

    /// The app's own dot at the top-left of two text lines: green when Claude Code is connected, red when not.
    /// Not a template image, so the dot keeps its color; the lines follow the menu bar's text color.
    private static func icon(connected: Bool) -> NSImage {
        let image = NSImage(size: CGSize(width: 18, height: 14), flipped: false) { _ in
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: CGRect(x: 8, y: 9.2, width: 9, height: 2), xRadius: 1, yRadius: 1).fill()
            NSBezierPath(roundedRect: CGRect(x: 1, y: 3, width: 16, height: 2), xRadius: 1, yRadius: 1).fill()
            (connected ? NSColor.systemGreen : NSColor.systemRed).setFill()
            NSBezierPath(ovalIn: CGRect(x: 1, y: 8.5, width: 5, height: 5)).fill()
            return true
        }
        image.accessibilityDescription = connected ? "Dot, connected" : "Dot, not connected"
        return image
    }

    /// Built each time the menu opens, so the token counts and status are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        switch auth.state {
        case .connected(let expiresSoon):
            menu.addItem(info("Anthropic account connected", dot: .systemGreen))
            menu.addItem(info("Model: Claude Haiku"))
            if expiresSoon { menu.addItem(info("Login expires tomorrow")) }
            menu.addItem(action("Disconnect Anthropic Account…", #selector(disconnect)))
        case .disconnected:
            menu.addItem(info("Anthropic account not connected", dot: .systemRed))
            menu.addItem(action("Connect Anthropic Account…", #selector(connect)))
        }
        if needsAccessibility { menu.addItem(action("Allow Accessibility…", #selector(allowAccessibility))) }
        if slackNeedsRestart { menu.addItem(action("Restart Slack to turn on checking", #selector(restartSlack))) }
        menu.addItem(.separator())
        let t = Usage.shared.ledger.totals(now: Date())
        menu.addItem(NSMenuItem.sectionHeader(title: "Tokens used"))
        menu.addItem(info("Today: \(shortCount(t.today))"))
        menu.addItem(info("This week: \(shortCount(t.week))"))
        menu.addItem(info("This month: \(shortCount(t.month))"))
        menu.addItem(.separator())
        menu.addItem(action("Setup…", #selector(setup)))
        if let app = NSWorkspace.shared.frontmostApplication, !isBlockedApp(app.bundleIdentifier, blocked: Settings.blockedApps) {
            let item = action("Don't Check in \(app.localizedName ?? "This App")", #selector(blockApp))
            item.representedObject = app.bundleIdentifier
            menu.addItem(item)
        }
        if let site = currentSite?() {
            let item = action("Don't Check on \(site)", #selector(blockSite))
            item.representedObject = site
            menu.addItem(item)
        }
        menu.addItem(action("Blocked Sites & Apps…", #selector(sites)))
        let login = action("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Dot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func info(_ title: String, dot: NSColor? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let dot {
            let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .regular).applying(.init(paletteColors: [dot])))
            menuItem.image = image
        }
        menuItem.isEnabled = false
        return menuItem
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    @objc private func connect() { auth.startConnectFlow() }

    @objc private func disconnect() {
        let alert = NSAlert()
        alert.messageText = "Disconnect your Anthropic account?"
        alert.informativeText = "This signs out Claude Code on this Mac, so Terminal and other tools that use it are signed out too. Underlines keep working; Rephrase and Make It Shorter stop until you connect again."
        alert.addButton(withTitle: "Disconnect")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await auth.disconnect() }
    }
    @objc private func allowAccessibility() { Permissions.openSettings() }
    @objc private func restartSlack() { Slack.restartSlackWithAccessibility() }
    @objc private func setup() { onSetup?() }
    @objc private func sites() { onSites?() }
    @objc private func blockApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Settings.blockedApps += [id]
        onBlockChanged?()
    }
    @objc private func blockSite(_ sender: NSMenuItem) {
        guard let site = sender.representedObject as? String else { return }
        Settings.blockedSites += [site]
        onBlockChanged?()
    }
    @objc private func toggleLogin() {
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() } else { try? SMAppService.mainApp.register() }
    }
}
