import AppKit
import SwiftUI

@main struct PlanExamples {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent("docs/plan-examples")
        let examples = [
            ("free", "Free", "Five-hour + weekly"),
            ("go", "Go", "Five-hour + weekly"),
            ("plus", "Plus", "Five-hour allowance running low"),
            ("pro-weekly", "Pro · weekly", "Matches your current allowance layout"),
            ("pro-two-windows", "Pro · two windows", "Both shown when the account reports both"),
            ("business", "Business", "Allowances + workspace credits"),
            ("enterprise", "Enterprise", "Example of a credits-only account"),
            ("edu", "Edu", "Allowances without credit or reset details"),
            ("plus-exhausted", "Plus · five-hour limit reached", "Credits take priority; both limits stay visible")
        ]
        for (name, title, subtitle) in examples {
            let data = try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/Plans/\(name).json"))
            let limits = try JSONDecoder().decode(LimitsResponse.self, from: data)
            let preferences = UserDefaults(suiteName: "codex-fuel-render-\(UUID().uuidString)")!
            let store = UsageStore(operations: UsageOperations(fetch: { Snapshot(limits: limits) }, reset: { _ in .nothingToReset }), preferences: preferences)
            store.snapshot = Snapshot(limits: limits)
            store.connectionError = nil
            let content = VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 16, weight: .semibold))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.horizontal, 6)
                UsagePanel(store: store, updater: AppUpdater())
                    .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 24))
                Text("SAMPLE DATA · Actual windows come from your account")
                    .font(.system(size: 9)).foregroundStyle(.secondary).padding(.horizontal, 6)
            }
            .padding(24).background(Color(white: 0.07))
            .environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: content)
            host.appearance = NSAppearance(named: .darkAqua)
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Unable to render \(name)") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG conversion") }
            try png.write(to: output.appendingPathComponent(name + ".png"))
            print("Rendered \(name): \(limits.main.windows.count) windows, menu \(limits.main.primaryMenuValue)")
        }
        let images = try examples.map { name, _, _ -> NSImage in
            guard let image = NSImage(contentsOf: output.appendingPathComponent(name + ".png")) else { throw NSError(domain: "Examples", code: 1) }
            return image
        }
        let cellWidth = images.map { $0.size.width }.max()!
        let cellHeight = images.map { $0.size.height }.max()!
        let sheet = NSImage(size: NSSize(width: cellWidth * 3, height: cellHeight * 3))
        sheet.lockFocus()
        NSColor(white: 0.07, alpha: 1).setFill()
        NSRect(origin: .zero, size: sheet.size).fill()
        for (index, image) in images.enumerated() {
            let x = CGFloat(index % 3) * cellWidth
            let y = sheet.size.height - CGFloat(index / 3) * cellHeight - image.size.height
            image.draw(at: NSPoint(x: x, y: y), from: .zero, operation: .sourceOver, fraction: 1)
        }
        sheet.unlockFocus()
        let bitmap = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("all-plans.png"))
    }
}
