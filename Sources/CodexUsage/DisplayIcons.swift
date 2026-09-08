import SwiftUI

/// Paths supplied for the panel's pin and presentation controls.
struct PinTackIcon: Shape {
    var filled = false
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 10, y: 17)); p.addLine(to: CGPoint(x: 10, y: 13))
        p.move(to: CGPoint(x: 10, y: 13)); p.addLine(to: CGPoint(x: 16, y: 13))
        p.addCurve(to: CGPoint(x: 15.3333, y: 10.75), control1: CGPoint(x: 15.9474, y: 12.4813), control2: CGPoint(x: 15.7988, y: 11.654))
        p.addCurve(to: CGPoint(x: 14, y: 9), control1: CGPoint(x: 14.9029, y: 9.9141), control2: CGPoint(x: 14.3713, y: 9.3421))
        p.addLine(to: CGPoint(x: 14, y: 6))
        p.addCurve(to: CGPoint(x: 11, y: 3), control1: CGPoint(x: 14, y: 4.3431), control2: CGPoint(x: 12.6569, y: 3))
        p.addLine(to: CGPoint(x: 9, y: 3))
        p.addCurve(to: CGPoint(x: 6, y: 6), control1: CGPoint(x: 7.3431, y: 3), control2: CGPoint(x: 6, y: 4.3431))
        p.addLine(to: CGPoint(x: 6, y: 9))
        p.addCurve(to: CGPoint(x: 4.6667, y: 10.75), control1: CGPoint(x: 5.6287, y: 9.3421), control2: CGPoint(x: 5.0963, y: 9.9141))
        p.addCurve(to: CGPoint(x: 4, y: 13), control1: CGPoint(x: 4.2012, y: 11.654), control2: CGPoint(x: 4.0526, y: 12.4813))
        p.closeSubpath()
        var result = p.strokedPath(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        if filled { result.addPath(p) }
        return result.applying(CGAffineTransform(scaleX: rect.width / 20, y: rect.height / 20))
    }
}

struct PresentationIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var outline = Path()
        outline.move(to: CGPoint(x: 6.21011, y: 17.8447))
        outline.addCurve(to: CGPoint(x: 1.5, y: 13.4534), control1: CGPoint(x: 4.01419, y: 16.5307), control2: CGPoint(x: 2.42621, y: 14.7116))
        outline.addLine(to: CGPoint(x: 1.5, y: 10.5466))
        outline.addCurve(to: CGPoint(x: 12, y: 4.5), control1: CGPoint(x: 3.10536, y: 8.3658), control2: CGPoint(x: 6.69879, y: 4.5))
        outline.addCurve(to: CGPoint(x: 17.7942, y: 6.1579), control1: CGPoint(x: 14.2447, y: 4.5), control2: CGPoint(x: 16.1832, y: 5.1931))
        outline.move(to: CGPoint(x: 9.52513, y: 14.4749))
        outline.addCurve(to: CGPoint(x: 9.52513, y: 9.52517), control1: CGPoint(x: 8.15829, y: 13.1081), control2: CGPoint(x: 8.15829, y: 10.892))
        outline.addCurve(to: CGPoint(x: 14.4749, y: 9.52517), control1: CGPoint(x: 10.892, y: 8.15833), control2: CGPoint(x: 13.108, y: 8.15833))
        var p = outline.strokedPath(StrokeStyle(lineWidth: 2))
        var slash = Path()
        slash.move(to: CGPoint(x: 21.5, y: 2.5)); slash.addLine(to: CGPoint(x: 2.5, y: 21.5))
        p.addPath(slash.strokedPath(StrokeStyle(lineWidth: 2, lineCap: .square)))
        p.move(to: CGPoint(x: 20.9434, y: 7.2998))
        p.addCurve(to: CGPoint(x: 23.3057, y: 9.9541), control1: CGPoint(x: 21.9564, y: 8.24208), control2: CGPoint(x: 22.7478, y: 9.1963))
        p.addLine(to: CGPoint(x: 23.5, y: 10.2178)); p.addLine(to: CGPoint(x: 23.5, y: 13.7812)); p.addLine(to: CGPoint(x: 23.3057, y: 14.0459))
        p.addCurve(to: CGPoint(x: 12, y: 20.5), control1: CGPoint(x: 21.658, y: 16.2841), control2: CGPoint(x: 17.8038, y: 20.5))
        p.addCurve(to: CGPoint(x: 8.33301, y: 19.9102), control1: CGPoint(x: 10.6774, y: 20.5), control2: CGPoint(x: 9.45352, y: 20.2768))
        p.addLine(to: CGPoint(x: 9.96094, y: 18.2822))
        p.addCurve(to: CGPoint(x: 12, y: 18.5), control1: CGPoint(x: 10.6069, y: 18.4206), control2: CGPoint(x: 11.2863, y: 18.5))
        p.addCurve(to: CGPoint(x: 21.5, y: 13.1162), control1: CGPoint(x: 16.6096, y: 18.5), control2: CGPoint(x: 19.865, y: 15.254))
        p.addLine(to: CGPoint(x: 21.5, y: 10.8809))
        p.addCurve(to: CGPoint(x: 19.5283, y: 8.71484), control1: CGPoint(x: 21.003, y: 10.2313), control2: CGPoint(x: 20.3417, y: 9.46462))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            NSColor.black.setFill()
            let context = NSGraphicsContext.current!.cgContext
            context.addPath(PresentationIcon().path(in: rect).cgPath)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Balances hidden"
        return image
    }
}

/// Exact filled brain-nodes path supplied for the reasoning badge.
struct ReasoningIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 8.25, y: 2.07292))
        p.addCurve(to: CGPoint(x: 6.75, y: 1.5), control1: CGPoint(x: 7.85193, y: 1.71664), control2: CGPoint(x: 7.32627, y: 1.5))
        p.addCurve(to: CGPoint(x: 3.7687, y: 4.16306), control1: CGPoint(x: 5.2067, y: 1.5), control2: CGPoint(x: 3.93608, y: 2.66454))
        p.addCurve(to: CGPoint(x: 1.5, y: 7.25), control1: CGPoint(x: 2.45717, y: 4.57666), control2: CGPoint(x: 1.5, y: 5.79341))
        p.addCurve(to: CGPoint(x: 4.5, y: 10), control1: CGPoint(x: 1.5, y: 8.8998), control2: CGPoint(x: 3, y: 10))
        p.addCurve(to: CGPoint(x: 2.15747, y: 10.3352), control1: CGPoint(x: 4, y: 10.5), control2: CGPoint(x: 3.09124, y: 10.6846))
        p.addCurve(to: CGPoint(x: 2, y: 11.25), control1: CGPoint(x: 2.05575, y: 10.6203), control2: CGPoint(x: 2, y: 10.9279))
        p.addCurve(to: CGPoint(x: 3.76564, y: 13.8083), control1: CGPoint(x: 2, y: 12.4255), control2: CGPoint(x: 2.73715, y: 13.4144))
        p.addCurve(to: CGPoint(x: 6.75, y: 16.5), control1: CGPoint(x: 3.9199, y: 15.3206), control2: CGPoint(x: 5.19686, y: 16.5))
        p.addCurve(to: CGPoint(x: 8.25, y: 15.9271), control1: CGPoint(x: 7.32626, y: 16.5), control2: CGPoint(x: 7.85193, y: 16.2834))
        p.addLine(to: CGPoint(x: 8.25, y: 12.914))
        p.addCurve(to: CGPoint(x: 8.17667, y: 12.7373), control1: CGPoint(x: 8.25, y: 12.8479), control2: CGPoint(x: 8.22398, y: 12.7846))
        p.addLine(to: CGPoint(x: 7.38853, y: 11.9492))
        p.addCurve(to: CGPoint(x: 7, y: 12), control1: CGPoint(x: 7.26461, y: 11.9823), control2: CGPoint(x: 7.13437, y: 12))
        p.addCurve(to: CGPoint(x: 5.5, y: 10.5), control1: CGPoint(x: 6.1716, y: 12), control2: CGPoint(x: 5.5, y: 11.3284))
        p.addCurve(to: CGPoint(x: 7, y: 9), control1: CGPoint(x: 5.5, y: 9.6716), control2: CGPoint(x: 6.1716, y: 9))
        p.addCurve(to: CGPoint(x: 8.5, y: 10.5), control1: CGPoint(x: 7.8284, y: 9), control2: CGPoint(x: 8.5, y: 9.6716))
        p.addCurve(to: CGPoint(x: 8.44919, y: 10.8885), control1: CGPoint(x: 8.5, y: 10.6344), control2: CGPoint(x: 8.48233, y: 10.7646))
        p.addLine(to: CGPoint(x: 9.23733, y: 11.6767))
        p.addCurve(to: CGPoint(x: 9.75, y: 12.914), control1: CGPoint(x: 9.56602, y: 12.0054), control2: CGPoint(x: 9.75, y: 12.4501))
        p.addLine(to: CGPoint(x: 9.75, y: 15.9271))
        p.addCurve(to: CGPoint(x: 11.25, y: 16.5), control1: CGPoint(x: 10.1481, y: 16.2834), control2: CGPoint(x: 10.6737, y: 16.5))
        p.addCurve(to: CGPoint(x: 14.2344, y: 13.8083), control1: CGPoint(x: 12.8031, y: 16.5), control2: CGPoint(x: 14.0801, y: 15.3206))
        p.addCurve(to: CGPoint(x: 16, y: 11.25), control1: CGPoint(x: 15.2628, y: 13.4144), control2: CGPoint(x: 16, y: 12.4255))
        p.addCurve(to: CGPoint(x: 15.8425, y: 10.3352), control1: CGPoint(x: 16, y: 10.9279), control2: CGPoint(x: 15.9442, y: 10.6203))
        p.addCurve(to: CGPoint(x: 13.5, y: 10), control1: CGPoint(x: 14.9088, y: 10.6846), control2: CGPoint(x: 14, y: 10.5))
        p.addCurve(to: CGPoint(x: 16.5, y: 7.25), control1: CGPoint(x: 15, y: 10), control2: CGPoint(x: 16.5, y: 8.8998))
        p.addCurve(to: CGPoint(x: 14.2313, y: 4.16306), control1: CGPoint(x: 16.5, y: 5.79341), control2: CGPoint(x: 15.5428, y: 4.57666))
        p.addCurve(to: CGPoint(x: 11.25, y: 1.5), control1: CGPoint(x: 14.0639, y: 2.66454), control2: CGPoint(x: 12.7933, y: 1.5))
        p.addCurve(to: CGPoint(x: 9.75, y: 2.07292), control1: CGPoint(x: 10.6737, y: 1.5), control2: CGPoint(x: 10.1481, y: 1.71664))
        p.addLine(to: CGPoint(x: 9.75, y: 5.086))
        p.addCurve(to: CGPoint(x: 9.82333, y: 5.26267), control1: CGPoint(x: 9.75, y: 5.15214), control2: CGPoint(x: 9.77602, y: 5.21536))
        p.addLine(to: CGPoint(x: 10.6115, y: 6.05081))
        p.addCurve(to: CGPoint(x: 11, y: 6), control1: CGPoint(x: 10.7354, y: 6.01767), control2: CGPoint(x: 10.8656, y: 6))
        p.addCurve(to: CGPoint(x: 12.5, y: 7.5), control1: CGPoint(x: 11.8284, y: 6), control2: CGPoint(x: 12.5, y: 6.6716))
        p.addCurve(to: CGPoint(x: 11, y: 9), control1: CGPoint(x: 12.5, y: 8.3284), control2: CGPoint(x: 11.8284, y: 9))
        p.addCurve(to: CGPoint(x: 9.5, y: 7.5), control1: CGPoint(x: 10.1716, y: 9), control2: CGPoint(x: 9.5, y: 8.3284))
        p.addCurve(to: CGPoint(x: 9.55081, y: 7.11147), control1: CGPoint(x: 9.5, y: 7.36563), control2: CGPoint(x: 9.51767, y: 7.23539))
        p.addLine(to: CGPoint(x: 8.76267, y: 6.32333))
        p.addCurve(to: CGPoint(x: 8.25, y: 5.086), control1: CGPoint(x: 8.43398, y: 5.99464), control2: CGPoint(x: 8.25, y: 5.54986))
        p.addLine(to: CGPoint(x: 8.25, y: 2.07292))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width / 18, y: rect.height / 18))
    }
}
