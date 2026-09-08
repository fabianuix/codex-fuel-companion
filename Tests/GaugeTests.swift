import AppKit

@main struct GaugeTests {
    static func main() throws {
        precondition(abs(GaugeIcon.angle(remaining: 0) - (3 * .pi / 4)) < 0.00001)
        precondition(abs(GaugeIcon.angle(remaining: 50) - (25 * .pi / 16)) < 0.00001)
        precondition(abs(GaugeIcon.angle(remaining: 100) - 19 * .pi / 8) < 0.00001)
        precondition(GaugeIcon.angle(remaining: -10) == GaugeIcon.angle(remaining: 0))
        precondition(GaugeIcon.angle(remaining: 110) == GaugeIcon.angle(remaining: 100))
        let values: [Double?] = [100, 75, 50, 25, 0, nil]
        let rendered = values.map { value -> Data in
            let image = GaugeIcon.image(remaining: value)
            precondition(image.isTemplate)
            precondition(image.size == NSSize(width: 18, height: 18))
            return image.tiffRepresentation!
        }
        precondition(Set(rendered).count == 6, "Each gauge position, including unavailable, must be distinct")
        let preview = NSImage(size: NSSize(width: 560, height: 80), flipped: false) { _ in
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 560, height: 80).fill()
            for (index, value) in values.enumerated() {
                let icon = GaugeIcon.image(remaining: value)
                icon.isTemplate = false
                icon.draw(in: NSRect(x: index * 80 + 25, y: 35, width: 30, height: 30))
                let label = value.map { "\(Int($0))%" } ?? "Unknown"
                (label as NSString).draw(at: NSPoint(x: index * 80 + 19, y: 12), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black])
            }
            let coins = CoinsIcon.image()
            coins.isTemplate = false
            coins.draw(in: NSRect(x: 505, y: 35, width: 30, height: 30))
            ("Credits" as NSString).draw(at: NSPoint(x: 499, y: 12), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black])
            return true
        }
        let bitmap = NSBitmapImageRep(data: preview.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/codex-gauge-check.png"))
        precondition(!Credits(hasCredits: true, unlimited: false, balance: "10").isDepleted)
        precondition(Credits(hasCredits: false, unlimited: false, balance: "0").isDepleted)
        precondition(Credits(hasCredits: false, unlimited: false, balance: "-1").isDepleted)
        precondition(!Credits(hasCredits: true, unlimited: true, balance: "0").isDepleted)
        precondition(!Credits(hasCredits: true, unlimited: false, balance: nil).isDepleted)
        precondition(CoinsIcon.image().isTemplate)
        precondition(CoinsIcon.image().tiffRepresentation == CoinsIcon.image().tiffRepresentation)
        precondition(!rendered.contains(CoinsIcon.image().tiffRepresentation!))
        print("PASS: gauge endpoints, clamping, template rendering, and six distinct states")
    }
}
