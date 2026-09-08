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
        print("PASS: all shortcut recorder interaction checks")
    }
}
