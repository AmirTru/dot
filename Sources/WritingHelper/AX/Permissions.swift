import AppKit
import ApplicationServices

@MainActor
enum Permissions {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func ask() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
