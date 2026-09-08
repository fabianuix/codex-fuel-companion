import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

func render(width: Int, height: Int, scale: Int = 1, draw: () -> Void) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}
func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let context = NSGraphicsContext.current!.cgContext
    context.saveGState()
    // AppKit text draws in an unflipped context; flip locally into the top-down design.
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    let height = (value as NSString).size(withAttributes: attributes).height
    context.translateBy(x: x, y: y + height)
    context.scaleBy(x: 1, y: -1)
    (value as NSString).draw(at: .zero, withAttributes: attributes)
    context.restoreGState()
}
let ink = NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.15, alpha: 1)
let icon = render(width: 1024, height: 1024) {
 let context = NSGraphicsContext.current!.cgContext
 context.setFillColor(NSColor.black.cgColor)
 context.addPath(CGPath(roundedRect: CGRect(x:72,y:72,width:880,height:880),cornerWidth:196,cornerHeight:196,transform:nil)); context.fillPath()
 context.translateBy(x: 200,y: 200); context.scaleBy(x:26,y:26)
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

 let colors = [NSColor(calibratedRed:0.80,green:0.53,blue:0.34,alpha:1).cgColor,NSColor(calibratedRed:0.81,green:0.55,blue:0.75,alpha:1).cgColor,NSColor(calibratedRed:0.76,green:0.49,blue:0.94,alpha:1).cgColor,NSColor(calibratedRed:0.88,green:0.72,blue:1,alpha:1).cgColor]
 let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),colors:colors as CFArray,locations:[0,0.35,0.7,1])!
 func drawRing() { context.saveGState(); context.addPath(ring);context.clip();context.drawLinearGradient(gradient,start:CGPoint(x:1,y:12),end:CGPoint(x:23,y:12),options:[]);context.restoreGState() }
 for blur in [CGFloat(1.2),0.45] {
 context.saveGState(); context.setShadow(offset:.zero,blur:blur*26,color:NSColor(calibratedRed:0.76,green:0.49,blue:0.94,alpha:blur>1 ? 0.35:0.6).cgColor);context.beginTransparencyLayer(auxiliaryInfo:nil);drawRing();context.endTransparencyLayer();context.restoreGState()
 }
 drawRing()
 context.setStrokeColor(NSColor(calibratedWhite:247.0/255,alpha:1).cgColor);context.setLineWidth(2);context.setLineCap(.square)
 context.move(to:CGPoint(x:5,y:5));context.addLine(to:CGPoint(x:10,y:10));context.addLine(to:CGPoint(x:9.61851,y:9.61851));context.strokePath()
 context.strokeEllipse(in:CGRect(x:9,y:9,width:6,height:6))
}
try icon.representation(using: .png, properties: [:])!.write(to: resources.appendingPathComponent("AppIcon.png"))

let background = render(width: 660, height: 420, scale: 2) {
    NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.95, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 660, height: 420).fill()
    text("Codex Fuel", x: 46, y: 36, size: 32, weight: .semibold, color: ink)
    text("Your Codex usage. A glance away.", x: 47, y: 82, size: 14, weight: .regular, color: NSColor(calibratedWhite: 0.46, alpha: 1))
    NSColor.black.withAlphaComponent(0.055).setFill()
    NSBezierPath(roundedRect: NSRect(x: 553, y: 44, width: 61, height: 28), xRadius: 14, yRadius: 14).fill()
    text("v" + (ProcessInfo.processInfo.environment["CODEX_FUEL_VERSION"] ?? "1.02"), x: 569, y: 49, size: 12, weight: .medium, color: ink)
    let context = NSGraphicsContext.current!.cgContext
    context.setStrokeColor(NSColor(calibratedWhite: 0.67, alpha: 1).cgColor)
    context.setLineWidth(3)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: 307, y: 211))
    context.addLine(to: CGPoint(x: 353, y: 211))
    context.move(to: CGPoint(x: 342, y: 200))
    context.addLine(to: CGPoint(x: 353, y: 211))
    context.addLine(to: CGPoint(x: 342, y: 222))
    context.strokePath()
    NSColor.black.withAlphaComponent(0.09).setFill()
    NSRect(x: 46, y: 323, width: 568, height: 1).fill()
    text("Drag Codex Fuel to Applications", x: 203, y: 347, size: 14, weight: .medium, color: ink)
    text("Then open it from Applications and look in your menu bar.", x: 151, y: 373, size: 12, weight: .regular, color: NSColor(calibratedWhite: 0.46, alpha: 1))
}
try background.representation(using: .tiff, properties: [:])!.write(to: resources.appendingPathComponent("InstallerBackground.tiff"))
try background.representation(using: .png, properties: [:])!.write(to: resources.appendingPathComponent("InstallerBackground.png"))
print("Rendered Codex Fuel icon and installer artwork")
