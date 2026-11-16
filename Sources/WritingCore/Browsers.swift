import Foundation

/// How an app exposes its text inputs. Browsers in one family behave the same way; every other app is `.other`.
public enum AppFamily: Sendable, Equatable {
    case slack, firefox, safari, chromium, other
    public var isBrowser: Bool { self == .firefox || self == .safari || self == .chromium }
}

public func appFamily(bundleID: String?) -> AppFamily {
    switch bundleID ?? "" {
    case "com.tinyspeck.slackmacgap": return .slack
    case "app.zen-browser.zen", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
         "io.gitlab.librewolf-community", "net.waterfox.waterfox", "org.torproject.torbrowser":
        return .firefox
    case "com.apple.Safari", "com.apple.SafariTechnologyPreview": return .safari
    case "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
         "org.chromium.Chromium", "company.thebrowser.Browser", "company.thebrowser.dia", "com.microsoft.edgemac",
         "com.brave.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "com.kagi.kagimacOS":
        return .chromium
    default: return .other
    }
}

/// Sign-in and password pages: blocked until the person removes them.
public let defaultBlockedSites = ["accounts.google.com", "appleid.apple.com", "login.microsoftonline.com", "login.live.com",
                                  "my.1password.com", "vault.bitwarden.com", "id.atlassian.com"]

/// Password managers and terminals (which often show secrets): blocked until the person removes them.
public let defaultBlockedApps = ["com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.apple.Passwords",
                                 "com.apple.keychainaccess", "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
                                 "dev.warp.Warp-Stable"]

/// A listed site also covers its subdomains.
public func isBlockedSite(_ url: String?, blocked: [String]) -> Bool {
    guard let host = site(of: url) else { return false }
    return blocked.contains { host == $0 || host.hasSuffix("." + $0) }
}

/// The site a page belongs to, as a list entry: "https://www.GitHub.com/x" → "github.com".
public func site(of url: String?) -> String? {
    guard let url, let parts = URLComponents(string: url), parts.scheme == "https" || parts.scheme == "http",
          var host = parts.host?.lowercased(), host.contains(".") else { return nil }
    if host.hasPrefix("www.") { host.removeFirst(4) }
    return host
}

/// Dot never reads its own windows.
public func isBlockedApp(_ bundleID: String?, blocked: [String]) -> Bool {
    guard let bundleID else { return true }
    return bundleID == "local.dot.app" || blocked.contains(bundleID)
}

/// Turns what someone typed ("https://www.GitHub.com/acme") into a list entry ("github.com").
public func normalizedSite(_ typed: String) -> String? {
    var s = typed.trimmingCharacters(in: .whitespaces).lowercased()
    if !s.contains("://") { s = "https://" + s }
    guard var host = URLComponents(string: s)?.host, host.contains("."), !host.contains(" ") else { return nil }
    if host.hasPrefix("www.") { host.removeFirst(4) }
    return host
}

public enum SlackStep: Sendable, Equatable { case notInstalled, needsOpen, needsRestart, done }

/// Slack only shows its message box to Dot when it was started with the accessibility flag.
public func slackStep(installed: Bool, running: Bool, hasFlag: Bool) -> SlackStep {
    guard installed else { return .notInstalled }
    guard running else { return .needsOpen }
    return hasFlag ? .done : .needsRestart
}
