import SwiftUI

@MainActor private final class UpdateMotion: ObservableObject {
    @Published var hovered = false
    @Published var spinning = false
}

struct UpdateBadge: View {
    @ObservedObject var updater: AppUpdater
    var openSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = UpdateMotion()
    private let blue = Color(red: 2.0 / 255, green: 133.0 / 255, blue: 1)
    var body: some View {
        Button { updater.installUpdate() } label: {
            HStack(spacing: 5) {
                if updater.phase.busy { UpdateSpinner().frame(width: 11, height: 11) }
                Text(updater.phase.busy ? "Updating…" : "UPDATE")
                    .font(.system(size: 10, weight: .semibold)).fixedSize()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9).frame(height: 22)
            .background {
                Capsule().fill(blue)
                    .overlay { Capsule().fill(.black.opacity(motion.hovered ? 0.08 : 0)) }
                    .overlay(alignment: .leading) {
                        if let progress = updater.progress, updater.phase == .downloading {
                            GeometryReader { geometry in
                                Rectangle().fill(.white.opacity(0.15))
                                    .frame(width: geometry.size.width * progress)
                            }.clipShape(Capsule())
                        }
                    }
            }
            .animation(reduceMotion ? nil : .timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.22), value: updater.phase)
            .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.08), value: updater.progress)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!updater.phase.busy)
        .onHover { motion.hovered = $0 }
        .help(updater.phase.busy ? "Updating Codex Fuel. The app will reopen automatically." : "Install version \(updater.version) and restart Codex Fuel")
        .accessibilityLabel(updater.phase.busy ? "Updating Codex Fuel" : "Update Codex Fuel to version \(updater.version)")
        .accessibilityValue(updater.progress.map { "\(Int($0 * 100)) percent downloaded" } ?? "")
        .contextMenu { Button("Settings", action: openSettings) }
    }
}

struct UpdateSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = UpdateMotion()
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 1.5)
            Circle().trim(from: 0, to: 0.68).stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(motion.spinning && !reduceMotion ? 360 : 0))
        }
        .onAppear { motion.spinning = true }
        .animation(reduceMotion ? nil : .linear(duration: 0.9).repeatForever(autoreverses: false), value: motion.spinning)
        .accessibilityHidden(true)
    }
}
