import Testing
@testable import WritingCore

@Test func knowsAppFamilies() {
    #expect(appFamily(bundleID: "com.tinyspeck.slackmacgap") == .slack)
    #expect(appFamily(bundleID: "app.zen-browser.zen") == .firefox)
    #expect(appFamily(bundleID: "org.mozilla.firefox") == .firefox)
    #expect(appFamily(bundleID: "com.apple.Safari") == .safari)
    #expect(appFamily(bundleID: "com.google.Chrome") == .chromium)
    #expect(appFamily(bundleID: "company.thebrowser.Browser") == .chromium)
    #expect(appFamily(bundleID: "com.microsoft.edgemac") == .chromium)
    #expect(appFamily(bundleID: "com.brave.Browser") == .chromium)
    #expect(appFamily(bundleID: "com.apple.TextEdit") == .other)
    #expect(appFamily(bundleID: nil) == .other)
}

@Test func blockedSitesAreSkipped() {
    let blocked = ["accounts.google.com", "bank.example"]
    #expect(isBlockedSite("https://accounts.google.com/signin", blocked: blocked))
    #expect(isBlockedSite("https://www.bank.example/login", blocked: blocked))
    #expect(!isBlockedSite("https://mail.google.com/", blocked: blocked))
    #expect(!isBlockedSite("https://notbank.example/", blocked: blocked))
    #expect(!isBlockedSite("https://github.com/acme", blocked: blocked))
}

@Test func siteOfPage() {
    #expect(site(of: "https://www.GitHub.com/acme/web") == "github.com")
    #expect(site(of: "about:blank") == nil)
    #expect(site(of: nil) == nil)
}

@Test func dotNeverChecksItselfOrBlockedApps() {
    #expect(isBlockedApp("local.dot.app", blocked: []))
    #expect(isBlockedApp("com.1password.1password", blocked: ["com.1password.1password"]))
    #expect(!isBlockedApp("com.apple.TextEdit", blocked: ["com.1password.1password"]))
    #expect(isBlockedApp(nil, blocked: []))
}

@Test func siteEntriesAreCleanedUp() {
    #expect(normalizedSite(" https://www.GitHub.com/acme ") == "github.com")
    #expect(normalizedSite("linear.app") == "linear.app")
    #expect(normalizedSite("not a site") == nil)
}
