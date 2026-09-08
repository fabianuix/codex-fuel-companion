import AppKit

/// Load the current bundled artwork directly rather than relying on a cached application icon.
enum AppIdentity {
    static var icon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 64, height: 64))
    }
}
