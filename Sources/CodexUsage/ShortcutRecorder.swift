import SwiftUI
import Carbon

struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var store: UsageStore
    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onRecord = { store.shortcutRecording = $0 }
        button.onSave = { store.saveShortcut($0) }
        return button
    }
    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) {
        button.stopRecording()
    }
    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.shortcutTitle = store.shortcut.display
        button.refreshTitle()
    }
}

private final class RecorderLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class ShortcutRecorderButton: NSButton {
    var onRecord: ((Bool) -> Void)?
    var onSave: ((AppShortcut) -> Bool)?
    var shortcutTitle = ""
    private(set) var isRecording = false
    private var hovering = false
    private var resignObserver: NSObjectProtocol?
    private var clickMonitor: Any?
    private let displayLabel = RecorderLabel(labelWithString: "")
    private var previousBounds = CGRect.zero
    override var acceptsFirstResponder: Bool { true }
    init() {
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .inline
        font = .systemFont(ofSize: 11, weight: .medium)
        focusRingType = .none
        target = self
        action = #selector(beginRecording)
        toolTip = "Click to change keyboard shortcut"
        setAccessibilityLabel("Keyboard shortcut")
        displayLabel.font = font
        displayLabel.alignment = .center
        displayLabel.setAccessibilityElement(false)
        addSubview(displayLabel)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if let newWindow {
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: newWindow, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopRecording() }
            }
        } else { stopRecording() }
        super.viewWillMove(toWindow: newWindow)
    }
    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; refreshTitle() }
    override func mouseExited(with event: NSEvent) { hovering = false; refreshTitle() }
    override func layout() {
        super.layout()
        if bounds != previousBounds {
            previousBounds = bounds
            positionLabel()
        }
    }
    private func positionLabel() {
        let size = displayLabel.intrinsicContentSize
        let width = min(max(0, bounds.width - 12), size.width)
        let x = (bounds.width - width) / 2
        let frame = NSRect(x: x, y: (bounds.height - size.height) / 2, width: width, height: size.height)
        displayLabel.frame = frame
    }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        let focused = isRecording || (window?.isKeyWindow == true && window?.firstResponder === self)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) :
            NSColor.labelColor.withAlphaComponent(hovering || isHighlighted ? 0.10 : 0.055)).setFill()
        shape.fill()
        (focused ? NSColor.controlAccentColor.withAlphaComponent(0.7) :
            NSColor.labelColor.withAlphaComponent(0.10)).setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }
    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }
    func refreshTitle() {
        title = ""
        displayLabel.stringValue = isRecording ? "Type keys…" : shortcutTitle
        displayLabel.textColor = isRecording ? .labelColor : .secondaryLabelColor
        setAccessibilityValue(isRecording ? "Recording shortcut" : shortcutTitle)
        positionLabel()
        needsDisplay = true
    }
    @objc private func beginRecording() {
        if isRecording { stopRecording(); return }
        guard window?.makeFirstResponder(self) == true else { return }
        isRecording = true
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            if event.window !== self.window || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                self.stopRecording()
            }
            return event
        }
        onRecord?(true)
        refreshTitle()
    }
    func stopRecording(releaseFocus: Bool = true) {
        let wasRecording = isRecording
        isRecording = false
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
        if wasRecording { onRecord?(false) }
        highlight(false)
        if releaseFocus, window?.firstResponder === self { window?.makeFirstResponder(nil) }
        refreshTitle()
    }
    override func resignFirstResponder() -> Bool {
        stopRecording(releaseFocus: false)
        needsDisplay = true
        return super.resignFirstResponder()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { stopRecording(); return }
        if event.keyCode == 48 {
            stopRecording()
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
            return
        }
        let flags = event.modifierFlags
        guard flags.contains(.command) || flags.contains(.control),
              let key = event.charactersIgnoringModifiers?.uppercased(), !key.isEmpty,
              key.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            displayLabel.stringValue = "Use ⌘ / ⌃"
            positionLabel()
            setAccessibilityValue(displayLabel.stringValue)
            return
        }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let candidate = AppShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
        if onSave?(candidate) == true {
            shortcutTitle = candidate.display
            stopRecording()
        } else {
            displayLabel.stringValue = "Try another"
            positionLabel()
            setAccessibilityValue("Shortcut unavailable. Try another.")
        }
    }
}
