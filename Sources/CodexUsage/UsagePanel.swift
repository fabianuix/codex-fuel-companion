import SwiftUI

@MainActor private final class PanelNavigation: ObservableObject {
    @Published var showingSettings = false
    @Published var pageVisible = true
    @Published var scrollEdges = ScrollEdges()
    var transitionTask: Task<Void, Never>?
}

struct UsagePanel: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var updater: AppUpdater
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var navigation = PanelNavigation()
    var onConfirmQuit: (() -> Void)?
    var onSizeChange: ((Bool) -> Void)?
    @Namespace private var continuity
    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.9) }
    var body: some View {
        Group {
            if navigation.showingSettings {
                settingsPage
            } else {
                usagePage
            }
        }
        .onChange(of: updater.phase) {
            if updater.phase.busy && navigation.showingSettings { navigate(to: false) }
            if updater.testingUpdates && [.completed, .current, .failed].contains(updater.phase) && !navigation.showingSettings {
                navigate(to: true)
            }
        }
        .onChange(of: store.settingsRequest) { navigate(to: true) }
        .disabled(store.confirmingQuit || updater.showingDialog)
        .accessibilityHidden(store.confirmingQuit || updater.showingDialog)
        .overlay {
            if store.confirmingQuit || updater.showingDialog {
                RoundedRectangle(cornerRadius: 24).fill(.black.opacity(0.42))
                    .accessibilityHidden(true)
            }
        }
        .opacity(navigation.pageVisible ? 1 : 0)
        .offset(y: navigation.pageVisible || reduceMotion ? 0 : 6)
    }
    private func navigate(to settings: Bool) {
        navigation.transitionTask?.cancel()
        guard !reduceMotion else {
            navigation.showingSettings = settings
            navigation.pageVisible = true
            DispatchQueue.main.async { onSizeChange?(false) }
            return
        }
        navigation.transitionTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.10)) { navigation.pageVisible = false }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            navigation.showingSettings = settings
            // Let SwiftUI measure the destination before resizing the glass surface.
            await Task.yield()
            guard !Task.isCancelled else { return }
            onSizeChange?(true)
            withAnimation(.easeOut(duration: 0.22)) { navigation.pageVisible = true }
        }
    }
    private var usagePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if store.isStale {
                Label(store.snapshot.limits == nil ? "Unable to connect" : "Offline · last known balance", systemImage: "wifi.slash")
                    .font(.caption).foregroundStyle(.secondary)
                    .help(store.tooltip + "\n" + (store.connectionError ?? store.snapshot.limitsError ?? ""))
            }
            if let limits = store.snapshot.limits {
                if limits.main.usesCredits, store.showCreditBalance, let credits = limits.main.credits {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            MorphingText(text: credits.display, numericValue: credits.balance.flatMap(Double.init)).font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
                            if !credits.unlimited { Text("credits").font(.system(size: 12)).foregroundStyle(.secondary) }
                            if store.showBuyCredits { Spacer(); buyCreditsButton }
                        }
                    }.matchedGeometryEffect(id: "creditBalance", in: continuity)
                    if !limits.main.windows.isEmpty { Divider() }
                    ForEach(Array(limits.main.windows.enumerated()), id: \.offset) { index, window in
                        windowRow(window).matchedGeometryEffect(id: "window-\(index)", in: continuity)
                    }
                } else {
                    ForEach(Array(limits.main.windows.enumerated()), id: \.offset) { index, window in
                        windowRow(window).matchedGeometryEffect(id: "window-\(index)", in: continuity)
                    }
                    if limits.main.windows.isEmpty { Text("No usage limit reported").font(.caption).foregroundStyle(.secondary) }
                    if store.showCreditBalance, let credits = limits.main.credits {
                        Divider()
                        HStack {
                            HStack(spacing: 6) {
                                MorphingText(text: credits.display, numericValue: credits.balance.flatMap(Double.init)).fontWeight(.medium).monospacedDigit()
                                Text("credits").foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.showBuyCredits { buyCreditsButton }
                        }.font(.system(size: 13))
                            .matchedGeometryEffect(id: "creditBalance", in: continuity)
                            .help("Credit units reported by Codex. Currency conversion is not provided.")
                    }
                }
                if limits.main.credits == nil && store.showBuyCredits {
                    HStack { Spacer(); buyCreditsButton }
                }
            } else if store.refreshing {
                HStack { ProgressView().controlSize(.small); Text("Connecting…").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 16)
            }
            if let message = store.resetMessage {
                MorphingText(text: message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let error = store.loginError { Text(error).font(.caption).foregroundStyle(.orange) }
            if store.showResetRow {
                Divider()
                HStack {
                    MorphingText(text: store.snapshot.limits == nil ? "Resets unavailable" : store.hasPendingReset ? "Reset pending" : "\(store.availableResets) reset\(store.availableResets == 1 ? "" : "s") available", numericValue: store.hasPendingReset ? nil : Double(store.availableResets))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button { store.useReset() } label: {
                        HStack(spacing: 5) {
                            if store.isResetting { ProgressView().controlSize(.mini) }
                            MorphingText(text: store.isResetting ? "Resetting…" : (store.hasPendingReset ? "Check reset" : "Use reset"))
                        }
                    }.buttonStyle(PanelActionButtonStyle()).disabled(!store.canReset)
                        .help("Use one available reset to reset eligible Codex usage limits.")
                }
            }

        }
        .padding(22)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .animation(motion, value: store.snapshot.limits?.main.usesCredits)
        .animation(motion, value: store.showReset)
        .animation(motion, value: store.resetMessage)
    }
    private var buildLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let isDev = Bundle.main.object(forInfoDictionaryKey: "CodexFuelDevelopmentBuild") as? Bool == true
        return isDev ? "Dev · \(version) · build \(build)" : "Version \(version)"
    }
    private var buyCreditsButton: some View {
        Button("Buy credits…") { openBilling() }
            .buttonStyle(PanelActionButtonStyle())
    }
    private func openBilling() {
        NSWorkspace.shared.open(URL(string: "https://chatgpt.com/codex/settings/usage")!)
    }
    private var header: some View {
        HStack {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("Codex Fuel").font(.system(size: 14, weight: .semibold))
                if let plan = store.snapshot.limits?.planName {
                    Text(plan).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if updater.showsBadge {
                UpdateBadge(updater: updater, openSettings: { navigate(to: true) })
            } else {
            Button { navigate(to: true) } label: {
                SettingsGearIcon().fill(Color.primary, style: FillStyle(eoFill: true)).frame(width: 20, height: 20)
            }.buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Settings").accessibilityLabel("Settings")
            }
        }
    }
    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Button { navigate(to: false) } label: {
                    Image(systemName: "chevron.left").frame(width: 20, height: 20)
                }.buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help("Back to usage").accessibilityLabel("Back to usage")
                Text("Settings").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { onConfirmQuit?() } label: {
                    PowerOffIcon().stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .square))
                        .frame(width: 17, height: 17).frame(width: 24, height: 24)
                }.buttonStyle(.borderless).help("Quit Codex Fuel").accessibilityLabel("Quit Codex Fuel")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsSection("General") {
                        settingToggle("Always show Buy credits", isOn: $store.alwaysShowBuyCredits)
                        settingToggle("Always show available resets", isOn: $store.alwaysShowResets)
                        settingToggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: store.setLaunchAtLogin))
                        HStack {
                            Text("Keyboard shortcut")
                            Spacer()
                            ShortcutRecorder(store: store).frame(width: 88, height: 26)
                        }

                    }
                    Divider()
                    settingsSection("Notifications") {
                        settingToggle("Credits running low", isOn: Binding(get: { store.lowCreditAlerts }, set: { store.setAlerts(lowCredits: true, enabled: $0) }))
                        if store.lowCreditAlerts {
                            HStack {
                                Text("Notify below")
                                Spacer()
                                Picker("Notify below", selection: $store.creditThreshold) {
                                ForEach([50, 100, 250, 500, 1000], id: \.self) { amount in
                                    Text("\(amount) credits").tag(Double(amount))
                                }
                                }.pickerStyle(.menu).controlSize(.regular).labelsHidden()
                                    .fixedSize().frame(minHeight: 28)
                            }
                        }
                        settingToggle("Usage available again", isOn: Binding(get: { store.resetAlerts }, set: { store.setAlerts(lowCredits: false, enabled: $0) }))
                        Text("When your weekly allowance refreshes or a reset becomes available.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        if let error = store.optionError {
                            Text(error).font(.system(size: 11)).foregroundStyle(.orange)
                        }
                        if let error = store.loginError {
                            Text(error).font(.system(size: 11)).foregroundStyle(.orange)
                        }
                    }
                    Divider()
                    settingsSection("App updates") {
                        Text("Codex Fuel").fontWeight(.medium)
                        Text(buildLabel).font(.system(size: 11)).foregroundStyle(.secondary)
                        Button("Check for updates…") { updater.checkNow() }
                            .buttonStyle(PanelActionButtonStyle()).disabled(!updater.canCheck && !updater.showsBadge)
                        if updater.available {
                            settingToggle("Check automatically", isOn: Binding(get: { updater.automatic }, set: updater.setAutomatic))
                        } else {
                            Text(isDevelopmentBuild
                                 ? (updater.testingUpdates ? "Demo mode. Updates are simulated." : "You’re using a development copy. Update checks are available in the release app.")
                                 : updater.status)
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    VStack(spacing: 8) {
                        Button { openBilling() } label: {
                            Label("Manage credits", systemImage: "creditcard")
                                .fixedSize(horizontal: true, vertical: false).frame(maxWidth: .infinity)
                        }
                        Button { openCodex() } label: {
                            Label("Open Codex", systemImage: "arrow.up.right")
                                .fixedSize(horizontal: true, vertical: false).frame(maxWidth: .infinity)
                        }
                    }.buttonStyle(PanelActionButtonStyle())
                    if isDevelopmentBuild {
                        Divider()
                        settingsSection("Development") {
                            settingToggle("Test notifications", isOn: Binding(get: { store.testingNotifications }, set: { store.runNotificationTests?($0) }))
                            Text(store.notificationTestStatus ?? "Preview all three alerts, one every five seconds.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Divider()
                            settingToggle("Test updates", isOn: Binding(get: { updater.testingUpdates }, set: updater.setTestingUpdates))
                            Picker("Scenario", selection: $updater.demoScenario) {
                                ForEach(UpdateDemoScenario.allCases) { scenario in
                                    Text(scenario.rawValue).tag(scenario)
                                }
                            }.pickerStyle(.menu).controlSize(.regular)
                            if updater.testingUpdates {
                                Button("Run again") { updater.runDemo() }
                                    .buttonStyle(PanelActionButtonStyle())
                            }
                            Text(updater.demoStatus)
                                .font(.system(size: 11)).foregroundStyle(.secondary)

                        }
                    }
                }
                .font(.system(size: 12))
                .toggleStyle(.switch).controlSize(.mini).tint(.gray)
                .padding(.trailing, 18)
                .padding(.top, 6)
                .padding(.bottom, 22)
            }
            .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
                ScrollEdges(top: geometry.contentOffset.y > 1,
                            bottom: geometry.contentSize.height - geometry.containerSize.height - geometry.contentOffset.y > 1)
            } action: { _, edges in
                navigation.scrollEdges = edges
            }
            .modifier(ScrollEdgeTreatment(edges: navigation.scrollEdges))
            .padding(.trailing, -18)
            .frame(height: 452)
            .padding(.bottom, -22)

        }
        .padding(22).frame(width: 320)
    }
    private func settingToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 10)
            Toggle(title, isOn: isOn).labelsHidden()
        }
    }
    private var isDevelopmentBuild: Bool {
        Bundle.main.object(forInfoDictionaryKey: "CodexFuelDevelopmentBuild") as? Bool == true
    }
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func windowRow(_ window: LimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(window.title).foregroundStyle(.primary.opacity(0.88))
                Spacer()
                MorphingText(text: "\(Int(window.remaining))% left", numericValue: window.remaining).fontWeight(.medium).monospacedDigit()
            }.font(.system(size: 13))
            ProgressView(value: window.remaining, total: 100)
                .progressViewStyle(AllowanceProgressStyle(isLow: window.remaining <= 20, effort: store.reasoningEffort))
                .help(store.reasoningDescription)
                .accessibilityLabel("\(window.title), \(Int(window.remaining)) percent remaining")
                .accessibilityValue(store.reasoningDescription)
                .animation(motion, value: window.remaining)
            if let reset = window.reset {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    MorphingText(text: reset <= context.date ? "Reset due · refresh to update" : "Resets \(reset.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func openCodex() {
        guard let executable = CodexClient.executable(), executable.path.contains(".app/") else { return }
        NSWorkspace.shared.open(executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
    }
}

private struct ScrollEdges: Equatable {
    var top = false
    var bottom = false
}

/// Fade content into the existing glass without adding a second material surface.
private struct ScrollEdgeTreatment: ViewModifier {
    let edges: ScrollEdges
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let depth: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(edges.top ? 0 : 1), .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: depth)
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, .black.opacity(edges.bottom ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                        .frame(height: depth)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: edges)
            }
    }
}

struct PanelActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 11).padding(.vertical, 6)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.55))
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(isEnabled ? (configuration.isPressed ? 0.18 : 0.11) : 0.07))
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct PowerOffIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x / 24 * rect.width, y: rect.minY + y / 24 * rect.height) }
        p.move(to: point(8, 3.88068))
        p.addCurve(to: point(2.5, 12.5), control1: point(4.75197, 5.39055), control2: point(2.5, 8.6823))
        p.addCurve(to: point(12, 22), control1: point(2.5, 17.7467), control2: point(6.75329, 22))
        p.addCurve(to: point(21.5, 12.5), control1: point(17.2467, 22), control2: point(21.5, 17.7467))
        p.addCurve(to: point(16, 3.88068), control1: point(21.5, 8.6823), control2: point(19.248, 5.39055))
        p.move(to: point(12, 2))
        p.addLine(to: point(12, 11))
        return p
    }
}
