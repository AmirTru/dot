import ApplicationServices
import Foundation

enum AX {
    static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
    }

    static func param(_ el: AXUIElement, _ name: String, _ arg: AnyObject) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyParameterizedAttributeValue(el, name as CFString, arg, &value) == .success ? value : nil
    }

    @discardableResult
    static func set(_ el: AXUIElement, _ name: String, _ value: AnyObject) -> Bool {
        AXUIElementSetAttributeValue(el, name as CFString, value) == .success
    }

    static func rect(_ value: AnyObject?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var r = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &r) ? r : nil
    }

    static func range(_ value: AnyObject?) -> NSRange? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var r = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &r) ? NSRange(location: r.location, length: r.length) : nil
    }

    static func value(_ r: NSRange) -> AXValue {
        var c = CFRange(location: r.location, length: r.length)
        return AXValueCreate(.cfRange, &c)!
    }

    static func point(_ value: AnyObject?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &p) ? p : nil
    }

    static func size(_ value: AnyObject?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &s) ? s : nil
    }
}
