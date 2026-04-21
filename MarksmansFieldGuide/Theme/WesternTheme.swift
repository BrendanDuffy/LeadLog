import SwiftUI

// MARK: - Western Color Palette
//
// Matches the color constants from the React Native version exactly.

struct W {
    static let bg          = Color(rgb: 0x151210)
    static let surface     = Color(rgb: 0x1E1A14)
    static let parchment   = Color(rgb: 0xF5E6C8)
    static let parchmentDk = Color(rgb: 0xE8D5B0)
    static let brass       = Color(rgb: 0xC8A96E)
    static let wood        = Color(rgb: 0x8B6914)
    static let leather     = Color(rgb: 0x2A1F14)
    static let rust        = Color(rgb: 0x5C3D1E)
    static let text        = Color(rgb: 0xF2E8D5)
    static let textDark    = Color(rgb: 0x2A1F14)
    static let muted       = Color(rgb: 0x8A7A65)
    static let gold        = Color(rgb: 0xD4A017)
    static let error       = Color(rgb: 0xCD3700)
    static let warning     = Color(rgb: 0xD4A017)
    static let success     = Color(rgb: 0x4A7C59)

    // Gradient used for dark embossed buttons (Add, Submit, etc.)
    static let buttonGradient = LinearGradient(
        colors: [
            Color(rgb: 0x6B5B4E),
            Color(rgb: 0x4A3F35),
            Color(rgb: 0x2A1F14),
            Color(rgb: 0x1A1208),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Color Hex Init

extension Color {
    /// Create a Color from a 6-digit hex integer (e.g. 0xC8A96E)
    init(rgb hex: Int, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >>  8) & 0xFF) / 255.0,
            blue:  Double( hex        & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}

// MARK: - Western Fonts

extension Font {
    /// Rye — the primary western display font (titles, labels, buttons)
    static func rye(_ size: CGFloat) -> Font {
        .custom("Rye-Regular", size: size)
    }

    /// Playfair Display Bold — secondary serif (values, subtitles)
    static func playfairBold(_ size: CGFloat) -> Font {
        .custom("PlayfairDisplay-Bold", size: size)
    }

    /// Playfair Display Regular — body text
    static func playfairRegular(_ size: CGFloat) -> Font {
        .custom("PlayfairDisplay-Regular", size: size)
    }
}

// MARK: - Button Styles

/// Dark embossed gradient button — used for secondary actions
struct WesternGradientButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Group {
                    if isDestructive {
                        LinearGradient(
                            colors: [W.error.opacity(0.8), W.error],
                            startPoint: .top, endPoint: .bottom
                        )
                    } else {
                        W.buttonGradient
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        LinearGradient(
                            colors: [W.brass.opacity(0.35), Color.black.opacity(0.5)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Haptics

enum HapticType { case light, medium, success, error }

func haptic(_ type: HapticType = .light) {
    switch type {
    case .light:   UIImpactFeedbackGenerator(style: .light).impactOccurred()
    case .medium:  UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
    case .error:   UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
