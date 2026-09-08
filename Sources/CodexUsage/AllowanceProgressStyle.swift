import SwiftUI

/// The fill carries the glow; an exhausted allowance never leaves a luminous dot.
struct AllowanceProgressStyle: ProgressViewStyle {
    let isLow: Bool
    var effort: ReasoningEffort? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var colors: [Color] {
        ReasoningPalette.colors(effort: effort, isLow: isLow, colorScheme: colorScheme)
    }

    private var glowOpacity: Double {
        guard !reduceTransparency, contrast != .increased else { return 0 }
        let strength: Double
        if isLow { strength = 0.30 }
        else {
            switch effort {
            case .minimal: strength = 0.10
            case .low: strength = 0.17
            case .medium: strength = 0.23
            case .high: strength = 0.29
            case .xhigh: strength = 0.34
            case .max: strength = 0.38
            case .ultra: strength = 0.42
            default: strength = 0
            }
        }
        return colorScheme == .dark ? strength : strength * 0.48
    }

    func makeBody(configuration: Configuration) -> some View {
        let fraction = max(0, min(1, configuration.fractionCompleted ?? 0))
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(contrast == .increased ? 0.24 : 0.12))
                if fraction > 0 {
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .overlay {
                            Capsule().fill(LinearGradient(colors: [.white.opacity(0.36), .clear],
                                                          startPoint: .top, endPoint: .bottom))
                        }
                        .frame(width: geometry.size.width * fraction)
                        .shadow(color: colors[2].opacity(glowOpacity), radius: 4, x: 0, y: 0)
                        .shadow(color: colors[1].opacity(glowOpacity * 0.45), radius: 8, x: 0, y: 1)
                }
            }
        }
        .frame(height: 6)
    }
}

enum ReasoningPalette {
    static func colors(effort: ReasoningEffort?, isLow: Bool = false, colorScheme: ColorScheme) -> [Color] {
        if isLow {
            return [Color(red: 0.92, green: 0.39, blue: 0.17),
                    Color(red: 1, green: 0.62, blue: 0.29),
                    Color(red: 1, green: 0.81, blue: 0.53)]
        }
        if effort == .ultra {
            if colorScheme == .light {
                return [Color(red: 0.66, green: 0.39, blue: 0.27),
                        Color(red: 0.65, green: 0.34, blue: 0.66),
                        Color(red: 0.52, green: 0.28, blue: 0.79),
                        Color(red: 0.63, green: 0.39, blue: 0.87)]
            }
            return [Color(red: 0.80, green: 0.53, blue: 0.34),
                    Color(red: 0.81, green: 0.55, blue: 0.75),
                    Color(red: 0.76, green: 0.49, blue: 0.94),
                    Color(red: 0.88, green: 0.72, blue: 1)]
        }
        let hues: [Double]
        switch effort {
        case .minimal, .low: hues = [0.43, 0.46, 0.49]
        case .medium: hues = [0.49, 0.53, 0.57]
        case .high: hues = [0.55, 0.60, 0.65]
        case .xhigh: hues = [0.62, 0.68, 0.74]
        case .max: hues = [0.73, 0.80, 0.88]
        default:
            return [Color.primary.opacity(0.50), Color.primary.opacity(0.72), Color.primary.opacity(0.90)]
        }
        let dark = colorScheme == .dark
        return hues.enumerated().map { index, hue in
            Color(hue: hue, saturation: dark ? 0.47 - Double(index) * 0.06 : 0.68,
                  brightness: dark ? 0.87 + Double(index) * 0.06 : 0.70)
        }
    }
}
