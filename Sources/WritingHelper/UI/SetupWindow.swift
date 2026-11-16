import AppKit
import ServiceManagement
import SwiftUI
import WritingCore

/// The welcome window: three steps that turn green on their own as each one is done.
@MainActor
final class SetupWindow {
    private var window: NSWindow?
    private let model: SetupModel

    init(auth: AuthMonitor) { model = SetupModel(auth: auth) }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SetupView(model: model, finish: { [weak self] in self?.finish() }))
            w.center()
            window = w
        }
        model.start()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        Settings.finishedSetup = true
        if model.openAtLogin { try? SMAppService.mainApp.register() }
        model.stop()
        window?.close()
    }
}

@MainActor
final class SetupModel: ObservableObject {
    @Published var accessibility = false
    @Published var claudeInstalled = false
    @Published var claudeConnected = false
    @Published var openAtLogin = true
    @Published var connecting = false
    private let auth: AuthMonitor
    private var poll: Timer?
    private var ticks = 0

    init(auth: AuthMonitor) { self.auth = auth }

    var allDone: Bool { accessibility && claudeConnected }

    func start() {
        refresh()
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { self.refresh() } }
    }

    func stop() { poll?.invalidate(); poll = nil }

    private func refresh() {
        accessibility = Permissions.isTrusted
        claudeInstalled = ClaudePaths.isInstalled
        ticks += 1
        // `claude auth status` starts a process, so ask every 3 s.
        if ticks % 3 == 1, claudeInstalled { Task { await auth.refresh() } }
        if case .connected = auth.state, claudeInstalled { claudeConnected = true; connecting = false } else { claudeConnected = false }
    }

    func allowAccessibility() { Permissions.ask(); Permissions.openSettings() }
    func connect() { connecting = true; auth.startConnectFlow() }
}

private struct SetupView: View {
    @ObservedObject var model: SetupModel
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72).padding(.top, 28)
            Text("Welcome to Dot").font(.title2.bold()).padding(.top, 10)
            Text("A dot appears in your message when something needs fixing. A few quick steps to turn it on.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(width: 340).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            VStack(spacing: 0) {
                row(1, "Allow Accessibility", "Lets Dot see the text box you're typing in.", done: model.accessibility) {
                    Button("Open Settings") { model.allowAccessibility() }
                }
                Divider().padding(.leading, 50)
                row(2, "Connect Anthropic Account", nil, done: model.claudeConnected) {
                    if model.connecting { ProgressView().controlSize(.small) }
                    Button(model.claudeInstalled ? "Connect" : "Install") { model.connect() }
                }
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .padding(.horizontal, 24).padding(.top, 20)
            .animation(.snappy(duration: 0.25), value: model.accessibility)
            .animation(.snappy(duration: 0.25), value: model.claudeConnected)
            HStack {
                Toggle("Open Dot at login", isOn: $model.openAtLogin).toggleStyle(.checkbox).font(.callout)
                Spacer()
                Button("Start Using Dot", action: finish)
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(!model.allDone)
            }
            .padding(24)
        }
        .frame(width: 460)
    }

    private func row(_ n: Int, _ title: String, _ detail: String?, done: Bool, @ViewBuilder action: () -> some View) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.secondary.opacity(0.15)).frame(width: 24, height: 24)
                if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).transition(.scale) }
                else { Text("\(n)").font(.caption.bold()).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            if done { Text("Done").font(.callout).foregroundStyle(.secondary) } else { action() }
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
    }
}
