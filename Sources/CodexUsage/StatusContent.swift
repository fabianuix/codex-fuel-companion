import AppKit
import SwiftUI

private struct StatusBalance: View {
    var text: String
    var value: Double?
    var hidden = false
    var body: some View {
        Group {
            if hidden { Text(text) }
            else { MorphingText(text: text, numericValue: value) }
        }
            .font(.system(size: 12, weight: .medium)).monospacedDigit()
            .foregroundStyle(.primary)
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .allowsHitTesting(false)
    }
}
private final class StatusTextHost: NSHostingView<StatusBalance> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
private final class StatusIconView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Keep NSStatusBarButton as the actual clickable control. Both decorative subviews
/// deliberately pass through clicks, including the second click that dismisses the panel.
@MainActor final class StatusContent {
    private let item: NSStatusItem
    private var panelVisible = false
    private var lastText: String?
    private var lastValue: Double?
    private var lastHidden = false
    private let iconView = StatusIconView()
    private let textHost = StatusTextHost(rootView: StatusBalance(text: "", value: nil))
    var image: NSImage? {
        get { iconView.image }
        set { iconView.image = newValue }
    }
    init(item: NSStatusItem) {
        self.item = item
        guard let button = item.button else { return }
        button.title = ""
        button.image = nil
        iconView.imageScaling = .scaleProportionallyDown
        textHost.safeAreaRegions = []
        textHost.sizingOptions = []
        button.addSubview(iconView)
        button.addSubview(textHost)
        update(text: "—", value: nil)
    }
    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        item.button?.highlight(visible)
        // NSStatusBarButton clears its pressed appearance when mouse tracking
        // finishes, after invoking the action. Restore the native highlight on
        // the next turn, reading current visibility so a close cannot race it.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.item.button?.highlight(self.panelVisible)
        }
    }
    func update(text: String, value: Double?, hidden: Bool = false) {
        guard text != lastText || value != lastValue || hidden != lastHidden else { return }
        lastText = text; lastValue = value; lastHidden = hidden
        guard let button = item.button else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let width = text.isEmpty ? 0 : ceil((text as NSString).size(withAttributes: [.font: font]).width)
        item.length = 20 + (text.isEmpty ? 0 : 2 + width)
        let height = max(22, button.bounds.height)
        iconView.frame = NSRect(x: 1, y: (height - 18) / 2, width: 18, height: 18)
        textHost.isHidden = text.isEmpty
        textHost.frame = NSRect(x: 21, y: 0, width: width, height: height)
        textHost.rootView = StatusBalance(text: text, value: value, hidden: hidden)
        if panelVisible { button.highlight(true) }
        button.setAccessibilityLabel(text.isEmpty ? "Codex Fuel" : "Codex Fuel, \(text)")
    }
}
