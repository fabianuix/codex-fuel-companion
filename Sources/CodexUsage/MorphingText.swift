import SwiftUI

/// A native adaptation of Torph's number continuity and soft text replacement.
/// Only changed content animates; no timers run while the text is unchanged.
struct MorphingText: View {
    let text: String
    var numericValue: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Text(text)
            .contentTransition(reduceMotion ? .identity : numericValue.map { .numericText(value: $0) } ?? .interpolate)
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.9), value: text)
    }
}
