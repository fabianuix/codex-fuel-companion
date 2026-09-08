import AppKit
import Carbon
import UserNotifications

@MainActor final class SystemFeatures: NSObject, UNUserNotificationCenterDelegate {
    var onTestStatus: ((Bool, String?) -> Void)?
    private var notificationTestTask: Task<Void, Never>?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var toggle: (() -> Void)?
    private var enabled: Bool?
    private var registeredShortcut: AppShortcut?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<SystemFeatures>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { owner.toggle?() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func setShortcut(_ requested: Bool, shortcut: AppShortcut = .standard) -> Bool {
        if enabled == requested && (!requested || registeredShortcut == shortcut) { return !requested || hotKey != nil }
        if !requested {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil
            enabled = false
            return true
        }
        guard handler != nil, shortcut.isValid else { return false }
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x43555847, id: 1), GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr else { return false }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        registeredShortcut = shortcut
        enabled = true
        return true
    }
    func requestNotifications(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { allowed, _ in
            DispatchQueue.main.async { completion(allowed) }
        }
    }
    func notify(_ alert: UsageAlert, body: String) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: alert.rawValue, content: content, trigger: nil))
    }
    func testNotifications(_ enabled: Bool) {
        guard Bundle.main.object(forInfoDictionaryKey: "CodexFuelDevelopmentBuild") as? Bool == true else { return }
        notificationTestTask?.cancel()
        guard enabled else { onTestStatus?(false, "Notification test stopped."); return }
        onTestStatus?(true, "Checking notification permission…")
        notificationTestTask = Task { @MainActor in
            let allowed = await withCheckedContinuation { continuation in
                requestNotifications { continuation.resume(returning: $0) }
            }
            guard !Task.isCancelled else { return }
            guard allowed else { onTestStatus?(false, "Allow Codex Fuel notifications in System Settings to test alerts."); return }
            let samples: [(UsageAlert, String)] = [
                (.lowCredits, "You have 50 credits left. This is a test notification."),
                (.weeklyReset, "Your weekly Codex allowance is ready to use. This is a test notification."),
                (.resetAvailable, "Open Codex Fuel to use your available reset. This is a test notification.")
            ]
            for (index, sample) in samples.enumerated() {
                guard !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = sample.0.title
                content.body = sample.1
                content.sound = .default
                do {
                    try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "test-" + sample.0.rawValue, content: content, trigger: nil))
                } catch {
                    guard !Task.isCancelled else { return }
                    onTestStatus?(false, "Couldn’t send the test notification. Try again.")
                    return
                }
                guard !Task.isCancelled else { return }
                onTestStatus?(true, "\(index + 1) of 3 · \(sample.0.title)")
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
            onTestStatus?(false, "All three test notifications sent. Turn on to repeat.")
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.toggle?() }
        completionHandler()
    }
}
