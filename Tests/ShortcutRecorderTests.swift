import AppKit
import Carbon
@main struct RecorderChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:320,height:160), styleMask:[.borderless],backing:.buffered,defer:false)
        let button = ShortcutRecorderButton()
        button.frame = NSRect(x:210,y:80,width:88,height:26)
        button.shortcutTitle = AppShortcut.standard.display
        var recording = false
        var saves = 0
        button.onRecord = { recording = $0 }
        button.onSave = { _ in saves += 1; return true }
        window.contentView!.addSubview(button)
        func key(_ code: UInt16, _ text:String = "", _ flags:NSEvent.ModifierFlags = []) {
            button.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code)!)
        }
        func idle(_ label:String) {
            precondition(!button.isRecording && !recording && window.firstResponder !== button && !button.isHighlighted,label)
            print("PASS: " + label)
        }
        button.performClick(nil); precondition(button.isRecording && recording && window.firstResponder === button)
        key(UInt16(kVK_ANSI_K),"k",[.control,.option]); precondition(saves == 1); idle("save releases focus")
        button.performClick(nil); key(53); idle("Escape cancels and releases focus")
        button.performClick(nil); button.performClick(nil); idle("second click cancels and releases focus")
        button.performClick(nil); key(UInt16(kVK_ANSI_A),"a"); precondition(button.isRecording && saves == 1)
        key(53); idle("invalid shortcut can be cancelled")
        button.onSave = { _ in false }
        button.performClick(nil); key(UInt16(kVK_ANSI_K),"k",[.control]); precondition(button.isRecording)
        key(53); idle("unavailable shortcut can be cancelled")
        button.performClick(nil); window.makeFirstResponder(nil); idle("moving focus cancels recording")
        button.performClick(nil); NotificationCenter.default.post(name:NSWindow.didResignKeyNotification,object:window); idle("leaving window cancels recording")
        button.performClick(nil); key(48); idle("Tab exits recording")
        button.performClick(nil); button.removeFromSuperview(); idle("leaving Settings ends recording")
        let suite = "PanelOptionsTests-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = UsageStore(preferences: preferences)
        let panel = GlassPanel(store: store, updater: AppUpdater())
        panel.window.setFrame(NSRect(x: 100, y: 100, width: 320, height: 180), display: true)
        panel.window.orderFront(nil)
        precondition(panel.window.isVisible)
        panel.dismissForOutsideClick()
        precondition(!panel.window.isVisible, "Unpinned panel dismisses on outside clicks")
        store.panelPinned = true
        precondition(panel.window.level == .floating)
        panel.window.orderFront(nil)
        panel.dismissForOutsideClick()
        precondition(panel.window.isVisible, "Pinned panel stays visible")
        panel.window.cancelOperation(nil)
        precondition(!panel.window.isVisible, "Escape still dismisses a pinned panel")
        panel.window.orderFront(nil)
        panel.close()
        precondition(!panel.window.isVisible, "Explicit close still dismisses a pinned panel")
        store.panelPinned = false
        precondition(panel.window.level == .popUpMenu)
        if let screen = NSScreen.main?.visibleFrame {
        let desired = PinnedPanelPosition(x: screen.minX + 100, top: screen.maxY - 100)
        store.panelPinned = true
        store.savePinnedPosition(desired)
        let item = NSStatusBar.system.statusItem(withLength: 24)
        defer { NSStatusBar.system.removeStatusItem(item) }
        panel.toggle(from: item.button!)
        precondition(abs(panel.window.frame.minX - desired.x) < 1 && abs(panel.window.frame.maxY - desired.top) < 1)
        panel.window.isUserDragging = true
        panel.window.setFrameOrigin(NSPoint(x: screen.minX + 220, y: screen.minY + 200))
        let moved = panel.window.frame
        panel.resize()
        precondition(panel.window.frame == moved, "Refresh must not snap the window back during a drag")
        panel.window.isUserDragging = false
        panel.window.didFinishDragging?()
        precondition(store.pinnedPosition == PinnedPanelPosition(x: moved.minX, top: moved.maxY))
        let remembered = panel.window.frame
        panel.close(); panel.toggle(from: item.button!)
        precondition(panel.window.frame == remembered, "Reopening must restore the dragged position")
        let persisted = UsageStore(preferences: preferences)
        precondition(persisted.pinnedPosition == store.pinnedPosition)
        let larger = desired.frame(size: CGSize(width: 320, height: 450), in: screen)
        precondition(larger.maxY == desired.top, "Resizing must preserve the top of the panel")
        let disconnected = PinnedPanelPosition(x: -10000, top: 10000).frame(size: CGSize(width: 320, height: 200), in: screen)
        precondition(screen.contains(disconnected), "Disconnected displays must recover on a visible screen")
        let leftDisplay = CGRect(x: -1920, y: -200, width: 1920, height: 1000)
        let leftFrame = PinnedPanelPosition(x: -1800, top: 700).frame(size: CGSize(width: 320, height: 200), in: leftDisplay)
        precondition(leftFrame.minX == -1800 && leftFrame.maxY == 700)
        store.savePinnedPosition(nil)
        panel.resize()
        precondition(panel.window.frame != remembered, "Return to menu bar must clear the saved placement")
        panel.close()
        print("PASS: pinned drag persistence, reopen, no snapping during drag, resize anchoring and multi-display clamping")
        } else {
            print("SKIP: live display placement checks require a WindowServer display")
        }
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let status = StatusContent(item: statusItem)
        status.update(text: "25%", value: 25)
        precondition(statusItem.length > 20)
        status.update(text: "", value: nil)
        precondition(statusItem.length == 20 && statusItem.button?.accessibilityLabel() == "Codex Fuel")
        status.update(text: "2h 15m", value: nil)
        precondition(statusItem.length > 20 && statusItem.button?.accessibilityLabel() == "Codex Fuel, 2h 15m")
        status.update(text: "Hidden", value: nil, hidden: true)
        precondition(statusItem.button?.accessibilityLabel() == "Codex Fuel, Hidden")
        print("PASS: menu bar sizing and accessibility in percentage, countdown, icon-only and private modes")
        let virtualScreen = CGRect(x: -1920, y: -200, width: 1920, height: 1000)
        let clamped = PinnedPanelPosition(x: -9000, top: 9000).frame(size: CGSize(width: 320, height: 200), in: virtualScreen)
        precondition(virtualScreen.contains(clamped))
        let short = PinnedPanelPosition(x: -1800, top: 700).frame(size: CGSize(width: 320, height: 130), in: virtualScreen)
        let tall = PinnedPanelPosition(x: -1800, top: 700).frame(size: CGSize(width: 320, height: 450), in: virtualScreen)
        precondition(short.maxY == tall.maxY && short.minX == tall.minX)
        print("PASS: pin outside-click behavior, window level, Escape and explicit dismissal")
        print("PASS: all shortcut recorder interaction checks")
    }
}
