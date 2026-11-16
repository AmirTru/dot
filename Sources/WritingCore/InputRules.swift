import CoreGraphics

/// `secureInput` is macOS secure keyboard entry, which browsers and password managers turn on for password fields.
/// Code editors on the web (CodeMirror, Monaco, Google Docs) type into a tiny hidden box and draw the text elsewhere,
/// so no position can be found for their words: those inputs are skipped.
public func isEligibleInput(role: String, subrole: String?, editable: Bool, secureInput: Bool = false, size: CGSize? = nil) -> Bool {
    if secureInput || subrole == "AXSecureTextField" { return false }
    if let size, size.width < 20 || size.height < 8 { return false }
    switch role {
    case "AXTextArea", "AXTextField": return true
    case "AXWebArea", "AXGroup": return editable
    default: return false
    }
}

/// Password managers mark copied secrets so clipboard tools skip them and they can auto-clear.
/// Writing one back would reset that auto-clear, so such a clipboard is left empty instead.
public func shouldRestoreClipboard(types: [String]) -> Bool {
    !types.contains { $0 == "org.nspasteboard.ConcealedType" || $0 == "org.nspasteboard.TransientType" }
}
