import AppKit
import Combine
import Sparkle

enum AppUpdatePhase: Equatable {
    case idle, checking, available, downloading, extracting, installing, current, failed, completed
    var busy: Bool { [.downloading, .extracting, .installing].contains(self) }
}

enum UpdateDemoScenario: String, CaseIterable, Identifiable {
    case success = "Successful update"
    case current = "Already up to date"
    case checkFailure = "Connection failure"
    case downloadFailure = "Download failure"
    case installFailure = "Installation failure"
    var id: String { rawValue }
}

/// Sparkle owns verification, replacement and relaunch; this driver keeps its UI inside our panel.
@MainActor final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, SPUUserDriver {
    @Published private(set) var canCheck = false
    @Published private(set) var available = false
    @Published private(set) var automatic = true
    @Published private(set) var status = "Updates unavailable in this build"
    @Published private(set) var phase: AppUpdatePhase = .idle
    @Published private(set) var version = ""
    @Published private(set) var progress: Double?
    @Published var showingDialog = false
    @Published private(set) var testingUpdates = false
    @Published var demoScenario: UpdateDemoScenario = .success
    @Published private(set) var demoStatus = "Preview an update without changing the app."
    private let developmentBuild: Bool
    private let demoDelay: Duration
    private var demoTask: Task<Void, Never>?
    private var demoGeneration = UUID()
    init(developmentBuild: Bool = Bundle.main.object(forInfoDictionaryKey: "CodexFuelDevelopmentBuild") as? Bool == true,
         demoDelay: Duration = .seconds(1)) {
        self.developmentBuild = developmentBuild
        self.demoDelay = demoDelay
        super.init()
    }
    private var engine: SPUUpdater?
    private var observation: AnyCancellable?
    private var lastCheck: Date?
    private var choice: ((SPUUserUpdateChoice) -> Void)?
    private var cancellation: (() -> Void)?
    private var acknowledgement: (() -> Void)?
    private var installRequested = false
    private var informationURL: URL?
    private var informationOnly = false
    var updateActionTitle: String { informationOnly ? "View update" : "Update now" }
    private var expectedBytes: UInt64 = 0
    private var receivedBytes: UInt64 = 0
    var onCheckCompleted: ((Bool) -> Void)?
    var showsBadge: Bool { phase == .available || phase.busy }

    func start() {
        guard engine == nil else { return }
        guard !developmentBuild else {
            status = "Dev build · release updates disabled"
            return
        }
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              URL(string: feed)?.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else { return }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        do {
            // A click on UPDATE authorizes the download and restart.
            updater.automaticallyDownloadsUpdates = false
            try updater.start()
            engine = updater
            available = true
            automatic = updater.automaticallyChecksForUpdates
            status = "Automatic app updates"
            observation = updater.publisher(for: \.canCheckForUpdates)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.canCheck = $0 }
            checkInBackground()
        } catch { status = "Unable to start app updates" }
    }

    func setTestingUpdates(_ enabled: Bool) {
        guard developmentBuild, engine == nil else { return }
        testingUpdates = enabled
        resetDemo()
        canCheck = enabled
        if enabled { runDemo() }
        else {
            status = "Dev build · release updates disabled"
            demoStatus = "Preview an update without changing the app."
        }
    }
    private func resetDemo() {
        demoGeneration = UUID()
        demoTask?.cancel(); demoTask = nil
        choice = nil; cancellation = nil; acknowledgement = nil
        installRequested = false
        phase = .idle; progress = nil; version = ""
        showingDialog = false
    }
    func runDemo() {
        guard developmentBuild, engine == nil, testingUpdates else { return }
        resetDemo()
        let generation = demoGeneration
        let scenario = demoScenario
        demoStatus = "Checking for an update…"
        showUserInitiatedUpdateCheck { [weak self] in
            self?.demoTask?.cancel()
            self?.demoStatus = "Check cancelled. Run again to try another state."
        }
        demoTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: demoDelay * 2) } catch { return }
            guard testingUpdates, generation == demoGeneration else { return }
            switch scenario {
            case .current:
                demoStatus = "Up-to-date result. Choose another scenario or run again."
                showUpdateNotFoundWithError(demoError("You’re using the latest version of Codex Fuel."), acknowledgement: {})
            case .checkFailure:
                failDemo("The update check couldn’t connect. Please try again.")
            default:
                demoStatus = "Choose Update now, or Later to try the UPDATE badge."
                presentUpdate(version: "Demo", userInitiated: true) { [weak self] choice in
                    guard choice == .install else { return }
                    self?.downloadDemo(scenario: scenario, generation: generation)
                }
            }
        }
    }
    private func downloadDemo(scenario: UpdateDemoScenario, generation: UUID) {
        demoTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard testingUpdates, generation == demoGeneration else { return }
            demoStatus = "Downloading the demo update…"
            showDownloadInitiated(cancellation: {})
            showDownloadDidReceiveExpectedContentLength(100)
            for step in 1...10 {
                do { try await Task.sleep(for: demoDelay / 2) } catch { return }
                guard testingUpdates, generation == demoGeneration else { return }
                showDownloadDidReceiveData(ofLength: 10)
                if scenario == .downloadFailure && step == 5 {
                    failDemo("The download was interrupted. Check your connection and try again.")
                    return
                }
            }
            demoStatus = "Preparing the demo update…"
            showDownloadDidStartExtractingUpdate()
            do { try await Task.sleep(for: demoDelay * 2) } catch { return }
            guard testingUpdates, generation == demoGeneration else { return }
            showReady(toInstallAndRelaunch: { _ in })
            demoStatus = "Simulating installation and restart…"
            do { try await Task.sleep(for: demoDelay * 2) } catch { return }
            guard testingUpdates, generation == demoGeneration else { return }
            if scenario == .installFailure {
                failDemo("The update couldn’t be installed. Please try again.")
            } else {
                installRequested = false
                phase = .completed
                progress = nil
                status = "The demo finished successfully. No files were downloaded or installed, and the app wasn’t restarted."
                demoStatus = "Demo complete. Choose another scenario or run again."
                showingDialog = true
            }
        }
    }
    private func demoError(_ message: String) -> NSError {
        NSError(domain: "CodexFuel.UpdateDemo", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func failDemo(_ message: String) {
        demoStatus = "Failure preview. Choose another scenario or run again."
        showUpdaterError(demoError(message), acknowledgement: {})
    }

    func setAutomatic(_ enabled: Bool) {
        engine?.automaticallyChecksForUpdates = enabled
        automatic = enabled
    }
    func checkInBackground(now: Date = Date()) {
        guard let engine, automatic, !engine.sessionInProgress,
              lastCheck.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { return }
        lastCheck = now
        engine.checkForUpdatesInBackground()
    }
    func checkNow() {
        if testingUpdates && !showsBadge { runDemo(); return }
        showingDialog = true
        if showsBadge { return }
        guard canCheck else { return }
        dismissAcknowledgement()
        phase = .checking
        engine?.checkForUpdates()
    }
    func installUpdate() {
        guard phase == .available else { return }
        if informationOnly {
            if let informationURL { NSWorkspace.shared.open(informationURL) }
            else { showingDialog = true; status = "This update requires a manual download." }
            return
        }
        guard let reply = choice else { return }
        choice = nil
        installRequested = true
        showingDialog = false
        phase = .downloading
        progress = nil
        reply(.install)
    }
    func closeDialog() {
        showingDialog = false
        if phase == .checking {
            let cancel = cancellation; cancellation = nil
            phase = .idle
            cancel?()
        }
        dismissAcknowledgement()
    }
    private func dismissAcknowledgement() {
        let reply = acknowledgement; acknowledgement = nil
        reply?()
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        let succeeded = error == nil || (error as NSError?)?.code == Int(SUError.noUpdateError.rawValue)
        onCheckCompleted?(succeeded)
    }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: automatic, automaticUpdateDownloading: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        phase = .checking
        showingDialog = true
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        presentUpdate(version: appcastItem.displayVersionString, userInitiated: state.userInitiated,
                      informationURL: appcastItem.infoURL, informationOnly: appcastItem.isInformationOnlyUpdate, reply: reply)
    }
    // Also used by the isolated UI test host; never bypasses Sparkle's installer.
    func presentUpdate(version: String, userInitiated: Bool, informationURL: URL? = nil, informationOnly: Bool = false,
                       reply: @escaping (SPUUserUpdateChoice) -> Void) {
        cancellation = nil
        self.version = version
        self.informationURL = informationURL
        self.informationOnly = informationOnly
        choice = reply
        phase = .available
        progress = nil
        status = "Version \(version) is available"
        if userInitiated { showingDialog = true }
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        cancellation = nil
        self.acknowledgement = acknowledgement
        phase = .current
        status = error.localizedDescription
        showingDialog = true
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        cancellation = nil
        choice = nil
        installRequested = false
        self.acknowledgement = acknowledgement
        phase = .failed
        status = error.localizedDescription
        showingDialog = true
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        expectedBytes = 0; receivedBytes = 0
        phase = .downloading
        progress = nil
    }
    func showDownloadDidReceiveExpectedContentLength(_ length: UInt64) {
        expectedBytes = length
        updateProgress()
    }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        let sum = receivedBytes.addingReportingOverflow(length)
        receivedBytes = sum.overflow ? .max : sum.partialValue
        updateProgress()
    }
    private func updateProgress() {
        progress = expectedBytes > 0 ? min(1, Double(receivedBytes) / Double(expectedBytes)) : nil
    }
    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil
        phase = .extracting
        progress = nil
    }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if installRequested {
            phase = .installing
            progress = nil
            reply(.install)
        } else {
            choice = reply
            phase = .available
        }
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        phase = .installing
        progress = nil
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        phase = .current
        acknowledgement()
    }
    func dismissUpdateInstallation() {
        choice = nil; cancellation = nil; acknowledgement = nil
        installRequested = false
        if phase != .current && phase != .failed { phase = .idle }
    }
    func showUpdateInFocus() { showingDialog = true }
}
