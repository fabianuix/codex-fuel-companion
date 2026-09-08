import AppKit

/// The supplied gauge-2 SVG, drawn as a resolution-independent macOS template image.
enum GaugeIcon {
    static func angle(remaining: Double) -> Double {
        // Empty uses the old full position (135°); full uses the old 75%
        // position (67.5°), sweeping clockwise through the top of the dial.
        (135 + max(0, min(100, remaining)) * 2.925) * .pi / 180
    }
    static func image(remaining: Double?) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: 18 / 24, y: 18 / 24)
            // Rotate the entire supplied SVG, so its opening stays aligned with the needle.
            context.translateBy(x: 12, y: 12)
            context.rotate(by: angle(remaining: remaining ?? 0) - (-135 * .pi / 180))
            context.translateBy(x: -12, y: -12)
            context.setFillColor(NSColor.black.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)
            let ring = CGMutablePath()
            ring.move(to: CGPoint(x: 12, y: 1))
            ring.addCurve(to: CGPoint(x: 23, y: 12), control1: CGPoint(x: 18.0751, y: 1), control2: CGPoint(x: 23, y: 5.92487))
            ring.addCurve(to: CGPoint(x: 12, y: 23), control1: CGPoint(x: 23, y: 18.0751), control2: CGPoint(x: 18.0751, y: 23))
            ring.addCurve(to: CGPoint(x: 1, y: 12), control1: CGPoint(x: 5.92487, y: 23), control2: CGPoint(x: 1, y: 18.0751))
            ring.addCurve(to: CGPoint(x: 2.39355, y: 6.63574), control1: CGPoint(x: 1, y: 10.0539), control2: CGPoint(x: 1.50547, y: 8.22317))
            ring.addLine(to: CGPoint(x: 3.87793, y: 8.12012))
            ring.addCurve(to: CGPoint(x: 3, y: 12), control1: CGPoint(x: 3.31585, y: 9.29446), control2: CGPoint(x: 3, y: 10.6095))
            ring.addCurve(to: CGPoint(x: 12, y: 21), control1: CGPoint(x: 3, y: 16.9706), control2: CGPoint(x: 7.02944, y: 21))
            ring.addCurve(to: CGPoint(x: 21, y: 12), control1: CGPoint(x: 16.9706, y: 21), control2: CGPoint(x: 21, y: 16.9706))
            ring.addCurve(to: CGPoint(x: 12, y: 3), control1: CGPoint(x: 21, y: 7.02944), control2: CGPoint(x: 16.9706, y: 3))
            ring.addCurve(to: CGPoint(x: 8.11914, y: 3.87793), control1: CGPoint(x: 10.609, y: 3), control2: CGPoint(x: 9.29365, y: 3.31551))
            ring.addLine(to: CGPoint(x: 6.63574, y: 2.39453))
            ring.addCurve(to: CGPoint(x: 12, y: 1), control1: CGPoint(x: 8.22319, y: 1.50617), control2: CGPoint(x: 10.0536, y: 1))
            ring.closeSubpath()
            context.addPath(ring)
            context.fillPath()
            context.setLineWidth(2)
            context.setLineCap(.square)
            context.strokeEllipse(in: CGRect(x: 10, y: 10, width: 4, height: 4))
            // Keep the artwork complete while loading; dim the parked needle for unknown data.
            do {
                if remaining == nil { context.setAlpha(0.35) }
                let theta = -135 * Double.pi / 180
                context.move(to: CGPoint(x: 12 + cos(theta) * 2.12, y: 12 + sin(theta) * 2.12))
                context.addLine(to: CGPoint(x: 12 + cos(theta) * 9.9, y: 12 + sin(theta) * 9.9))
                context.strokePath()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = remaining.map { "Codex usage, \(Int($0)) percent remaining" } ?? "Codex usage unavailable"
        return image
    }
}
