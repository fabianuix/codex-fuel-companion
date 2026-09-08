import AppKit
import SwiftUI
import Combine

final class UsageWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    var dismiss: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { dismiss?() }
}

@MainActor private final class QuitAlertActions: NSObject {
    var finish: ((Bool) -> Void)?
    @objc func choose(_ sender: NSButton) { finish?(sender.tag == 1) }
}

@MainActor final class GlassPanel {
    let window: UsageWindow
    private let host: NSHostingView<UsagePanel>
    // Keep native alert presentation within the visible panel bounds.
    // AppKit supplies the exterior window shadow independently of its content.
    private let shadowInset: CGFloat = 0
    private var quitAlert: NSAlert?
    private var updateAlert: NSAlert?
    private let updateActions = QuitAlertActions()
    private var updateObservation: AnyCancellable?
    private var presentedUpdatePhase: AppUpdatePhase?
    private let quitActions = QuitAlertActions()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    var onVisibilityChange: ((Bool) -> Void)?
    private weak var anchor: NSStatusBarButton?
    init(store: UsageStore, updater: AppUpdater) {
        host = NSHostingView(rootView: UsagePanel(store: store, updater: updater))
        window = UsageWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.dismiss = { [weak self] in
            if store.confirmingQuit { self?.finishQuit(false) }
            else if updater.showingDialog { updater.closeDialog() }
            else { self?.close() }
        }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Codex Fuel"
        let canvas = NSView()
        canvas.wantsLayer = true
        canvas.layer?.cornerRadius = 24
        canvas.layer?.masksToBounds = true
        window.contentView = canvas
        let surface: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 24
            glass.contentView = host
            surface = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = 24
            material.layer?.masksToBounds = true
            material.addSubview(host)
            surface = material
        }
        updateObservation = updater.$showingDialog.combineLatest(updater.$phase, updater.$status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in self?.presentUpdateAlert() }
        host.rootView.onConfirmQuit = { [weak self] in self?.confirmQuit() }
        host.rootView.onSizeChange = { [weak self] animated in self?.resize(animated: animated) }
        canvas.addSubview(surface)
        surface.translatesAutoresizingMaskIntoConstraints = false
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: shadowInset),
            surface.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -shadowInset),
            surface.topAnchor.constraint(equalTo: canvas.topAnchor, constant: shadowInset),
            surface.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -shadowInset),
            host.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            host.topAnchor.constraint(equalTo: surface.topAnchor),
            host.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
    }

    private func layoutAlertWithoutIcon(_ alert: NSAlert) {
        alert.layout()
        guard let content = alert.window.contentView,
              let title = content.subviews.compactMap({ $0 as? NSTextField })
                .first(where: { $0.stringValue == alert.messageText }) else { return }
        // Preserve AppKit's text and button layout, removing the entire icon row.
        for image in content.subviews.compactMap({ $0 as? NSImageView }) {
            image.removeFromSuperview()
        }
        let titleTop = content.isFlipped ? title.frame.minY : title.frame.maxY
        let excess = content.isFlipped ? titleTop - 20 : content.bounds.height - titleTop - 20
        guard excess > 0 else { return }
        for view in content.subviews {
            view.autoresizingMask = []
            if content.isFlipped { view.setFrameOrigin(NSPoint(x: view.frame.minX, y: view.frame.minY - excess)) }
        }
        alert.window.setContentSize(NSSize(width: content.bounds.width, height: content.bounds.height - excess))
    }

    private func presentUpdateAlert() {
        let updater = host.rootView.updater
        guard updater.showingDialog else {
            removeUpdateAlert()
            return
        }
        guard quitAlert == nil, window.isVisible else { return }
        guard updateAlert == nil || presentedUpdatePhase != updater.phase else { return }
        removeUpdateAlert()
        let alert = NSAlert()
        alert.icon = NSImage(size: NSSize(width: 1, height: 1))
        alert.alertStyle = updater.phase == .failed ? .warning : .informational
        switch updater.phase {
        case .checking:
            alert.messageText = "Checking for updates…"
            alert.informativeText = "Looking for the latest version of Codex Fuel."
        case .available:
            alert.messageText = "Update available"
            alert.informativeText = "Version \(updater.version) is ready. Codex Fuel will reopen after updating."
        case .downloading, .extracting, .installing:
            alert.messageText = "Updating Codex Fuel…"
            alert.informativeText = "The app will reopen when the update is finished."
        case .failed:
            alert.messageText = "Couldn’t update Codex Fuel"
            alert.informativeText = updater.status
        case .completed:
            alert.messageText = "Update test complete"
            alert.informativeText = updater.status
        case .current:
            alert.messageText = "No update available"
            alert.informativeText = updater.status
        case .idle:
            alert.messageText = "App updates"
            alert.informativeText = updater.status
        }
        if updater.phase == .available {
            alert.addButton(withTitle: updater.updateActionTitle).tag = 1
            alert.addButton(withTitle: "Later").tag = 0
        } else {
            alert.addButton(withTitle: updater.phase == .checking ? "Cancel" : "OK").tag = 0
        }
        if updater.phase == .checking || updater.phase.busy {
            let spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 240, height: 20))
            spinner.style = .bar
            spinner.isIndeterminate = true
            spinner.startAnimation(nil)
            alert.accessoryView = spinner
        }
        updateActions.finish = { [weak self] install in
            guard let self else { return }
            if install { self.host.rootView.updater.installUpdate() }
            else { self.host.rootView.updater.closeDialog() }
        }
        for button in alert.buttons {
            button.target = updateActions
            button.action = #selector(QuitAlertActions.choose(_:))
        }
        alert.buttons.first?.keyEquivalent = "\r"
        if alert.buttons.count > 1 { alert.buttons.last?.keyEquivalent = "\u{1b}" }
        layoutAlertWithoutIcon(alert)
        updateAlert = alert
        presentedUpdatePhase = updater.phase
        window.addChildWindow(alert.window, ordered: .above)
        resize(animated: true)
        positionUpdateAlert()
        alert.window.makeKeyAndOrderFront(nil)
        // Native alerts can finalize their size after becoming visible.
        DispatchQueue.main.async { [weak self] in self?.resize(animated: false) }
    }

    private func positionUpdateAlert() {
        guard let alert = updateAlert else { return }
        let size = alert.window.frame.size
        alert.window.setFrameOrigin(NSPoint(x: window.frame.midX - size.width / 2,
                                           y: window.frame.midY - size.height / 2))
    }
    private func removeUpdateAlert() {
        guard let alert = updateAlert else { return }
        window.removeChildWindow(alert.window)
        alert.window.orderOut(nil)
        updateAlert = nil
        presentedUpdatePhase = nil
        resize(animated: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func confirmQuit() {
        guard quitAlert == nil else { return }
        let alert = NSAlert()
        alert.icon = NSImage(size: NSSize(width: 1, height: 1))
        alert.messageText = "Quit Codex Fuel?"
        alert.informativeText = "Your balance and notifications will return when you reopen the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        alert.buttons[0].tag = 1
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
        quitActions.finish = { [weak self] quit in self?.finishQuit(quit) }
        for button in alert.buttons {
            button.target = quitActions
            button.action = #selector(QuitAlertActions.choose(_:))
        }
        layoutAlertWithoutIcon(alert)
        quitAlert = alert
        host.rootView.store.confirmingQuit = true
        // Attach the native alert without AppKit's rectangular sheet backdrop.
        // The SwiftUI dimmer belongs to the rounded glass surface itself.
        window.addChildWindow(alert.window, ordered: .above)
        positionQuitAlert()
        alert.window.makeKeyAndOrderFront(nil)
    }

    private func positionQuitAlert() {
        guard let alert = quitAlert else { return }
        let size = alert.window.frame.size
        alert.window.setFrameOrigin(NSPoint(x: window.frame.midX - size.width / 2,
                                           y: window.frame.midY - size.height / 2))
    }

    private func finishQuit(_ quit: Bool) {
        guard let alert = quitAlert else { return }
        window.removeChildWindow(alert.window)
        alert.window.orderOut(nil)
        quitAlert = nil
        host.rootView.store.confirmingQuit = false
        if quit { NSApplication.shared.terminate(nil) }
        else { window.makeKeyAndOrderFront(nil) }
    }

    func resize(animated: Bool = false) {
        guard let anchor, let sourceWindow = anchor.window else { return }
        let rect = sourceWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let size = host.fittingSize
        let visible = sourceWindow.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let width = max(320, size.width) + shadowInset * 2
        let modalHeight = updateAlert.map { $0.window.frame.height + 44 } ?? 0
        let height = min(max(size.height, modalHeight), visible.height - 16) + shadowInset * 2
        let x = max(visible.minX + 8 - shadowInset, min(rect.midX - width / 2, visible.maxX - width - 8 + shadowInset))
        let y = max(visible.minY + 8 - shadowInset, rect.minY - height - 8 + shadowInset)
        let frame = NSRect(x: x, y: y, width: width, height: height)
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(frame, display: true)
            }, completionHandler: { [weak self] in
                DispatchQueue.main.async {
                    self?.positionQuitAlert()
                    self?.positionUpdateAlert()
                }
            })
        } else {
            window.setFrame(frame, display: true)
        }
        positionQuitAlert()
        positionUpdateAlert()
    }
    func toggle(from anchor: NSStatusBarButton) {
        if window.isVisible { close(); return }
        self.anchor = anchor
        resize()
        window.makeKeyAndOrderFront(nil)
        onVisibilityChange?(true)
        installMonitors()
        presentUpdateAlert()
    }
    func close() {
        guard !host.rootView.store.confirmingQuit, !host.rootView.updater.showingDialog else { return }
        (window.firstResponder as? ShortcutRecorderButton)?.stopRecording()
        window.orderOut(nil)
        onVisibilityChange?(false)
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
    private func isClickOnStatusButton() -> Bool {
        guard let anchor, let sourceWindow = anchor.window else { return false }
        let buttonFrame = sourceWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        return buttonFrame.contains(NSEvent.mouseLocation)
    }
    private func installMonitors() {
        // Remove old monitors after Escape also, before registering a new pair.
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.isClickOnStatusButton() else { return }
            self.close()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if self.host.rootView.updater.showingDialog {
                if event.type == .keyDown, event.keyCode == 53 { self.host.rootView.updater.closeDialog(); return nil }
                return event
            }
            if self.host.rootView.store.confirmingQuit {
                if event.type == .keyDown, event.keyCode == 53 { self.finishQuit(false); return nil }
                return event
            }
            if event.type == .keyDown, event.keyCode == 53 {
                if let recorder = self.window.firstResponder as? ShortcutRecorderButton, recorder.isRecording { return event }
                self.close(); return nil
            }
            if event.type != .keyDown, self.isClickOnStatusButton() { return event }
            if event.type != .keyDown, event.window != self.window, event.window != self.anchor?.window {
                // Native menus use a separate window; allow their normal interaction.
                if NSMenu.menuBarVisible(), event.window == nil { self.close() }
            }
            return event
        }
    }
}
