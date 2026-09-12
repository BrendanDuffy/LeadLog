import SwiftUI
import UIKit

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

    /// This color's RGB (no alpha) as a 24-bit int, e.g. `0x4D9D00` — the
    /// inverse of `init(rgb:)`, used to persist a user-picked accent color.
    var lgRGBHexValue: Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int((r * 255).rounded()) << 16) | (Int((g * 255).rounded()) << 8) | Int((b * 255).rounded())
    }
}

// MARK: - Haptics

enum HapticType { case light, medium, success, error }

func haptic(_ type: HapticType = .light) {
    let defaults = UserDefaults.standard
    let enabled = defaults.object(forKey: "soundEffectsEnabled") == nil || defaults.bool(forKey: "soundEffectsEnabled")
    guard enabled else { return }

    switch type {
    case .light:   UIImpactFeedbackGenerator(style: .light).impactOccurred()
    case .medium:  UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
    case .error:   UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

// MARK: - Transient input notice
// A field that silently filters or clamps a keystroke (digits-only, a max cap)
// should say so, briefly, instead of appearing to eat the input. This puts a
// short message in `binding` with a light haptic and clears it a couple of
// seconds later — only call it when a value was actually altered, never on
// every keystroke, so it stays informative rather than naggy.

@MainActor
func flashInputNotice(_ binding: Binding<String?>, _ message: String, seconds: Double = 2) {
    haptic(.light)
    withAnimation { binding.wrappedValue = message }
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(seconds))
        // Only clear if this same message is still showing — a fresh flash in
        // the meantime owns its own dismissal.
        if binding.wrappedValue == message {
            withAnimation { binding.wrappedValue = nil }
        }
    }
}

extension View {
    /// Renders `notice` as a small caption directly under the field it's
    /// attached to (used with `flashInputNotice`).
    @ViewBuilder
    func inputNotice(_ notice: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            self
            if let notice {
                Text(notice)
                    .font(LgFontPreference.font(size: 12))
                    .foregroundStyle(Color.lgWarning)
                    .transition(.opacity)
            }
        }
    }
}
