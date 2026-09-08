import SwiftUI

/// Only the empty header space moves the panel; badges and buttons keep their actions.
struct PanelDragHandle: NSViewRepresentable {
    let enabled: Bool
    func makeNSView(context: Context) -> PanelDragView { PanelDragView() }
    func updateNSView(_ view: PanelDragView, context: Context) {
        view.dragEnabled = enabled
        view.toolTip = enabled ? "Drag to move the pinned panel" : nil
        view.window?.invalidateCursorRects(for: view)
    }
}
final class PanelDragView: NSView {
    var dragEnabled = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { dragEnabled }
    override func resetCursorRects() {
        if dragEnabled { addCursorRect(bounds, cursor: .openHand) }
    }
    override func mouseDown(with event: NSEvent) {
        guard dragEnabled, let panel = window as? UsageWindow else { return }
        panel.isUserDragging = true
        NSCursor.closedHand.push()
        panel.performDrag(with: event)
        NSCursor.pop()
        panel.isUserDragging = false
        panel.didFinishDragging?()
    }
}
