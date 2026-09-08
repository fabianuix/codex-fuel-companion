import AppKit

/// The user's 20 × 20 coins SVG, with its original curves and rounded strokes.
/// macOS supplies the appropriate menu bar tint through template rendering.
enum CoinsIcon {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: 18 / 20, y: 18 / 20)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(2)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            let lower = CGMutablePath()
            lower.move(to: CGPoint(x: 3, y: 12.5))
            lower.addLine(to: CGPoint(x: 3, y: 14.5))
            lower.addCurve(to: CGPoint(x: 8.5, y: 17), control1: CGPoint(x: 3, y: 15.8807), control2: CGPoint(x: 5.4624, y: 17))
            lower.addCurve(to: CGPoint(x: 14, y: 14.5), control1: CGPoint(x: 11.5376, y: 17), control2: CGPoint(x: 14, y: 15.8807))
            lower.addLine(to: CGPoint(x: 14, y: 12.75))
            context.addPath(lower)
            context.strokePath()
            context.strokeEllipse(in: CGRect(x: 6, y: 3, width: 11, height: 5))
            let middle = CGMutablePath()
            middle.move(to: CGPoint(x: 4.5062, y: 10.7845))
            middle.addCurve(to: CGPoint(x: 3, y: 12.5), control1: CGPoint(x: 3.5748, y: 11.2323), control2: CGPoint(x: 3, y: 11.835))
            middle.addCurve(to: CGPoint(x: 8.5, y: 15), control1: CGPoint(x: 3, y: 13.8807), control2: CGPoint(x: 5.4625, y: 15))
            middle.addCurve(to: CGPoint(x: 13.9574, y: 12.7979), control1: CGPoint(x: 11.3154, y: 15), control2: CGPoint(x: 13.6329, y: 14.0378))
            context.addPath(middle)
            context.strokePath()
            let upper = CGMutablePath()
            upper.move(to: CGPoint(x: 6, y: 5.5))
            upper.addLine(to: CGPoint(x: 6, y: 7.5))
            upper.addCurve(to: CGPoint(x: 11.5, y: 10), control1: CGPoint(x: 6, y: 8.8807), control2: CGPoint(x: 8.4624, y: 10))
            upper.addCurve(to: CGPoint(x: 17, y: 7.5), control1: CGPoint(x: 14.5376, y: 10), control2: CGPoint(x: 17, y: 8.8807))
            upper.addLine(to: CGPoint(x: 17, y: 5.5))
            context.addPath(upper)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Codex credits"
        return image
    }
}
