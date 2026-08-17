import SwiftUI

// MARK: - Color Hex Init

extension Color {
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
