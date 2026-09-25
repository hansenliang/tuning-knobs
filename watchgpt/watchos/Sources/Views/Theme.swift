import SwiftUI

/// Design tokens from mockups/index.html: always-dark OLED, one amber tint that means "yours".
enum Theme {
    static let amber = Color(hex: 0xFFB547)
    static let amberDeep = Color(hex: 0xC77800)
    static let amberLight = Color(hex: 0xFFD08A)
    static let onAmber = Color(hex: 0x1A1000)
    static let micGlyph = Color(hex: 0x241500)
    static let dim = Color(hex: 0x9A9AA0)
    static let faint = Color(hex: 0x2A2A2E)
    static let card = Color(hex: 0x1C1C1F)
    static let bubble = Color(hex: 0x2C2C30)
    static let red = Color(hex: 0xFF453A)
    static let bright = Color(hex: 0xD6D6DA)

    static let body = Font.system(size: 16)
    static let small = Font.system(size: 13)
    static let bubbleFont = Font.system(size: 14.5)
    static let caption = Font.system(size: 14.5)
    static let button = Font.system(size: 15, weight: .semibold)

    /// `.mic`: radial-gradient(circle at 35% 30%, #FFD08A, amber 45%, amber-deep)
    static func micGradient(diameter: CGFloat) -> RadialGradient {
        RadialGradient(stops: [.init(color: amberLight, location: 0),
                               .init(color: amber, location: 0.45),
                               .init(color: amberDeep, location: 1)],
                       center: UnitPoint(x: 0.35, y: 0.30), startRadius: 0, endRadius: diameter * 0.75)
    }

    /// `.orb`: radial-gradient(circle at 40% 35%, #FFE2B0 0%, #FFB547 38%, #D77A00 70%, #5a2e00 100%)
    static func orbGradient(diameter: CGFloat) -> RadialGradient {
        RadialGradient(stops: [.init(color: Color(hex: 0xFFE2B0), location: 0),
                               .init(color: amber, location: 0.38),
                               .init(color: Color(hex: 0xD77A00), location: 0.70),
                               .init(color: Color(hex: 0x5A2E00), location: 1)],
                       center: UnitPoint(x: 0.40, y: 0.35), startRadius: 0, endRadius: diameter * 0.62)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// The mockup's `.btn`: a 38 pt capsule, either full width or round.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }

    var kind: Kind = .secondary
    var round = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, kind: kind, round: round)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let round: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Theme.button)
                .lineLimit(1)
                .foregroundStyle(foreground)
                .frame(maxWidth: round ? 38 : .infinity)
                .frame(width: round ? 38 : nil, height: 38)
                .background(background, in: Capsule())
                .contentShape(Capsule())
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
        }

        private var foreground: Color {
            switch kind {
            case .primary: Theme.onAmber
            case .secondary: .white
            case .destructive: Theme.red
            }
        }

        private var background: Color {
            switch kind {
            case .primary: Theme.amber
            case .secondary: Theme.card
            case .destructive: Theme.red.opacity(0.22)
            }
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static func pill(_ kind: PillButtonStyle.Kind = .secondary, round: Bool = false) -> PillButtonStyle {
        PillButtonStyle(kind: kind, round: round)
    }
}
