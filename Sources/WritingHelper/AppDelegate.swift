import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let auth = AuthMonitor()
    private var menuBar: MenuBar?
    private var controller: Controller?
    private let slackBanner = SlackBanner()
    private lazy var setupWindow = SetupWindow(auth: auth)
    private let sitesWindow = SitesWindow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bar = MenuBar(auth: auth)
        bar.onSetup = { [weak self] in self?.setupWindow.show() }
        bar.onSites = { [weak self] in self?.sitesWindow.show() }
        bar.currentSite = { [weak self] in self?.controller?.currentSite }
        bar.onBlockChanged = { [weak self] in self?.controller?.recheckBlocked() }
        menuBar = bar
        auth.start()
        if !Settings.finishedSetup { setupWindow.show() }
        if Permissions.isTrusted { startChecking() } else { waitForAccessibility() }
    }

    private func waitForAccessibility() {
        menuBar?.needsAccessibility = true
        if Settings.finishedSetup { Permissions.ask() }
        Task {
            while !Permissions.isTrusted { try? await Task.sleep(for: .seconds(2)) }
            menuBar?.needsAccessibility = false
            startChecking()
        }
    }

    private func startChecking() {
        let c = Controller(auth: auth)
        c.onSlackNeedsRestart = { [weak self] needs in
            self?.menuBar?.slackNeedsRestart = needs
            self?.slackBanner.update(needsRestart: needs)
        }
        c.start()
        controller = c
    }
}
