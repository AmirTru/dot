import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WritingCore

/// Sites and apps where Dot never reads text. Everything else is checked.
@MainActor
final class SitesWindow {
    private var window: NSWindow?
    private let model = BlockModel()

    func show() {
        model.reload()
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Blocked Sites & Apps"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: BlockView(model: model))
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class BlockModel: ObservableObject {
    @Published var sites: [String] = []
    @Published var apps: [String] = []
    @Published var draft = ""

    func reload() {
        sites = Settings.blockedSites
        apps = Settings.blockedApps
    }

    var canAdd: Bool { normalizedSite(draft) != nil }

    func addSite() {
        guard let site = normalizedSite(draft), !sites.contains(site) else { return }
        sites.append(site)
        Settings.blockedSites = sites
        draft = ""
    }

    func removeSite(_ site: String) {
        sites.removeAll { $0 == site }
        Settings.blockedSites = sites
    }

    func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        guard panel.runModal() == .OK, let id = panel.url.flatMap({ Bundle(url: $0)?.bundleIdentifier }), !apps.contains(id) else { return }
        apps.append(id)
        Settings.blockedApps = apps
    }

    func removeApp(_ id: String) {
        apps.removeAll { $0 == id }
        Settings.blockedApps = apps
    }

    /// Installed apps show their name and icon; ones that aren't installed show their bundle ID.
    func appLabel(_ id: String) -> (name: String, icon: NSImage?) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return (id, nil) }
        return (FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                NSWorkspace.shared.icon(forFile: url.path))
    }
}

private struct BlockView: View {
    @ObservedObject var model: BlockModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dot checks text everywhere except here. Password fields are never read.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List {
                Section("Sites") {
                    ForEach(model.sites, id: \.self) { site in
                        entry(Text(site), icon: nil) { model.removeSite(site) }
                    }
                    HStack {
                        TextField("example.com", text: $model.draft).onSubmit { model.addSite() }
                        Button("Add") { model.addSite() }.disabled(!model.canAdd)
                    }
                }
                Section("Apps") {
                    ForEach(model.apps, id: \.self) { id in
                        let label = model.appLabel(id)
                        entry(Text(label.name), icon: label.icon) { model.removeApp(id) }
                    }
                    Button("Add App…") { model.addApp() }
                }
            }
            .frame(height: 360)
        }
        .padding(16)
        .frame(width: 380)
    }

    private func entry(_ title: Text, icon: NSImage?, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            if let icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
            title
            Spacer()
            Button(action: remove) { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("Remove")
        }
    }
}
