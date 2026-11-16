import CoreGraphics

/// AX reports screen rects with a top-left origin on the primary screen; AppKit uses bottom-left.
public func axRectToAppKit(_ r: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
    CGRect(x: r.origin.x, y: primaryScreenHeight - r.origin.y - r.height, width: r.width, height: r.height)
}
