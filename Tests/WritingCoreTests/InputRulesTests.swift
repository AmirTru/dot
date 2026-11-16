import CoreGraphics
import Testing
@testable import WritingCore

@Test func passwordNeverEligible() { #expect(!isEligibleInput(role: "AXTextField", subrole: "AXSecureTextField", editable: true)) }
@Test func editableWebAreaEligible() { #expect(isEligibleInput(role: "AXWebArea", subrole: nil, editable: true)) }
@Test func readOnlyNotEligible() { #expect(!isEligibleInput(role: "AXWebArea", subrole: nil, editable: false)) }

@Test func nothingEligibleWhileSecureInputIsOn() {
    #expect(!isEligibleInput(role: "AXTextArea", subrole: nil, editable: true, secureInput: true))
    #expect(isEligibleInput(role: "AXTextArea", subrole: nil, editable: true, secureInput: false))
}

@Test func passwordManagerClipboardIsNotRestored() {
    #expect(!shouldRestoreClipboard(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
    #expect(!shouldRestoreClipboard(types: ["org.nspasteboard.TransientType"]))
    #expect(shouldRestoreClipboard(types: ["public.utf8-plain-text"]))
}

@Test func hiddenInputOfCodeEditorsIsSkipped() {
    #expect(!isEligibleInput(role: "AXTextArea", subrole: nil, editable: true, size: CGSize(width: 3, height: 1)))
    #expect(isEligibleInput(role: "AXTextArea", subrole: nil, editable: true, size: CGSize(width: 400, height: 40)))
}
