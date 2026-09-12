import SwiftUI
import UIKit

// MARK: - Adaptive color helper

extension Color {
    /// A color that resolves differently depending on the active light/dark appearance,
    /// re-evaluated live as the system (or an in-app override) switches themes.
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

// MARK: - Theme preference change notification
// Shared by every user-selectable theme preference below (accent color, font
// family, font size). Each one reads/writes plain `UserDefaults` and exposes
// its current value as a static computed property, not an observed binding —
// so the rest of the app (which just reads `Color.lgAccent*` / `Font.lg*` as
// plain values) needs an explicit signal to know when to refresh. `ContentView`
// listens for this once and force-remounts the whole tab view in response.

enum LgThemePreference {
    static let changedNotification = Notification.Name("LgThemePreferenceChanged")
}

// MARK: - User-selectable accent color
// The rest of the palette is fixed brand color, but the accent is themable:
// Settings offers 5 curated accent presets. We keep the picked color's hue
// (and saturation) but re-fit brightness into the same two bands the original
// lime accent used — a bright "fill" band (paired with dark content on top)
// and a darker/lighter "text" band per appearance — so any preset stays
// legible as a button fill and as standalone text/icon/border color, in both
// light and dark mode. Until a color is chosen, the palette is byte-identical
// to the original lime accent (no visual change for existing users).

enum LgAccentPreference {
    static let storageKey = "lgUserAccentColorHex"

    /// The raw color the user picked (before band-fitting) — `nil` means
    /// "still using the original lime accent."
    static var userColor: Color? {
        get {
            guard UserDefaults.standard.object(forKey: storageKey) != nil else { return nil }
            return Color(rgb: UserDefaults.standard.integer(forKey: storageKey))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.lgRGBHexValue, forKey: storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: storageKey)
            }
            NotificationCenter.default.post(name: LgThemePreference.changedNotification, object: nil)
        }
    }

    private static var hueSaturation: (hue: Double, saturation: Double)? {
        guard let userColor else { return nil }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(userColor).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Floor saturation so a *slightly* muted pick still reads as "a
        // color" rather than washing out — but leave a genuinely achromatic
        // pick (true gray, like the Dark Grey preset) alone, so it actually
        // renders as gray instead of picking up a stray hue tint.
        let flooredSaturation = s < 0.04 ? Double(s) : Double(min(max(s, 0.35), 1.0))
        return (Double(h), flooredSaturation)
    }

    /// A solid fill — always paired with dark content on top (buttons, progress, toggle).
    static func fill(dark: Bool) -> Color {
        guard let (h, s) = hueSaturation else {
            return dark ? Color(rgb: 0x7FD146) : Color(rgb: 0x4D9D00)
        }
        return Color(hue: h, saturation: dark ? min(s, 0.75) : s, brightness: dark ? 0.82 : 0.62)
    }

    /// Used directly as text/icon/border color against the page background.
    static func text(dark: Bool) -> Color {
        guard let (h, s) = hueSaturation else {
            return dark ? Color(rgb: 0x7FD146) : Color(rgb: 0x207200)
        }
        return Color(hue: h, saturation: dark ? min(s, 0.75) : s, brightness: dark ? 0.82 : 0.45)
    }
}

// MARK: - User-selectable font family & size
// Every piece of text in the app is built through `LgFontPreference.font(...)`
// (Theme's `lgMono`/`lgEyebrow`/`lgSectionLabel` tokens included) rather than
// calling `Font.system` directly, so a chosen family or size scale applies
// everywhere with no exceptions — including what would otherwise be the
// hardcoded monospaced "Optic Line" instrument accents (round counts, dates).
// That's a deliberate choice: the user asked for the picked family to
// override every piece of text, not just body copy.

enum LgFontFamily: String, CaseIterable, Identifiable {
    // System stays the default (nothing changes for anyone until they opt
    // in) — the other three are named fonts that ship with iOS itself (no
    // font files bundled with the app), chosen for a distinct, rugged,
    // tactical-brand feel: Impact (bold/commanding), Rockwell (industrial
    // slab serif), Copperplate (engraved insignia/badge look).
    case system, impact, rockwell, copperplate
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .impact: return "Impact"
        case .rockwell: return "Rockwell"
        case .copperplate: return "Copperplate"
        }
    }

    /// `nil` for `.system` (uses SwiftUI's dynamic system font instead of a
    /// named face). Broken out from `font(size:weight:)` — like
    /// `LgFontPreference.resolvedSize` — so the weight-to-face mapping is
    /// independently testable without relying on `Font`'s unreliable
    /// `Equatable` conformance. A `Font.custom` name that doesn't exist
    /// silently falls back to the system font, so these must match
    /// `UIFont.fontNames(forFamilyName:)` exactly (verified against the
    /// iOS 26 simulator runtime before picking them).
    func postscriptName(for weight: Font.Weight) -> String? {
        switch self {
        case .system:
            return nil
        case .impact:
            return "Impact" // one static weight only
        case .rockwell:
            switch weight {
            case .semibold, .bold, .heavy, .black: return "Rockwell-Bold"
            default: return "Rockwell-Regular"
            }
        case .copperplate:
            switch weight {
            case .semibold, .bold, .heavy, .black: return "Copperplate-Bold"
            case .light, .ultraLight, .thin: return "Copperplate-Light"
            default: return "Copperplate"
            }
        }
    }

    func font(size: CGFloat, weight: Font.Weight) -> Font {
        if let name = postscriptName(for: weight) {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight, design: .default)
    }
}

enum LgFontSizeOption: String, CaseIterable, Identifiable {
    case small, standard, large, extraLarge
    var id: String { rawValue }

    /// Multiplier applied to every point size in the app.
    var scale: CGFloat {
        switch self {
        case .small: return 0.9
        case .standard: return 1.0
        case .large: return 1.15
        case .extraLarge: return 1.3
        }
    }

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .standard: return "Default"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    /// Short glyph shown in the Settings preset button itself.
    var abbreviation: String {
        switch self {
        case .small: return "S"
        case .standard: return "M"
        case .large: return "L"
        case .extraLarge: return "XL"
        }
    }
}

enum LgFontPreference {
    private static let familyKey = "lgFontFamily"
    private static let sizeKey = "lgFontSizeOption"

    static var family: LgFontFamily {
        get {
            guard let raw = UserDefaults.standard.string(forKey: familyKey), let value = LgFontFamily(rawValue: raw) else { return .system }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: familyKey)
            NotificationCenter.default.post(name: LgThemePreference.changedNotification, object: nil)
        }
    }

    static var sizeOption: LgFontSizeOption {
        get {
            guard let raw = UserDefaults.standard.string(forKey: sizeKey), let value = LgFontSizeOption(rawValue: raw) else { return .standard }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: sizeKey)
            NotificationCenter.default.post(name: LgThemePreference.changedNotification, object: nil)
        }
    }

    /// Broken out from `font(size:weight:)` so the actual scaling math is
    /// independently testable — `SwiftUI.Font`'s `Equatable` conformance
    /// turns out not to reliably compare two separately-constructed values
    /// (even with identical parameters) for every weight, so tests can't
    /// safely assert against a hand-built `Font.system(...)` comparator.
    static func resolvedSize(for baseSize: CGFloat) -> CGFloat {
        baseSize * sizeOption.scale
    }

    /// The single chokepoint every font in the app is built through.
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        family.font(size: resolvedSize(for: size), weight: weight)
    }
}

// MARK: - Palette
// Neutral white-to-gray surfaces in light mode, neutral black-to-gray
// surfaces in dark mode — no cream/warm undertone in either — with a lime
// accent. Both share the same amber/red/blue status family.

extension Color {
    static let lgBackground = Color.adaptive(light: Color(rgb: 0xFFFFFF), dark: Color(rgb: 0x121212))
    static let lgCard = Color.adaptive(light: Color(rgb: 0xF7F7F5), dark: Color(rgb: 0x1E1E1E))
    static let lgCardAlt = Color.adaptive(light: Color(rgb: 0xEEEEEC), dark: Color(rgb: 0x212121))
    // Distinctly separated from lgCard so input wells read as their own fill.
    static let lgInput = Color.adaptive(light: Color(rgb: 0xEBEBE8), dark: Color(rgb: 0x242424))
    static let lgSheetBackground = Color.adaptive(light: Color(rgb: 0xFBFBFA), dark: Color(rgb: 0x181818))
    static let lgTabBar = Color.adaptive(light: Color(rgb: 0xFAFAF9), dark: Color(rgb: 0x141414))
    static let lgStatBlock = Color.adaptive(light: Color(rgb: 0xEEEEEC), dark: Color(rgb: 0x222222))
    static let lgProgressTrack = Color.adaptive(light: Color(rgb: 0xEBEBE8), dark: Color(rgb: 0x282828))
    static let lgProgressTrackDetail = Color.adaptive(light: Color(rgb: 0xDFDFDA), dark: Color(rgb: 0x353535))
    static let lgSegmentSelected = Color.adaptive(light: Color(rgb: 0xFFFFFF), dark: Color(rgb: 0x2A2A2A))

    static let lgText = Color.adaptive(light: Color(rgb: 0x18171A), dark: Color(rgb: 0xF2F2F2))
    static let lgTextSecondary = Color.adaptive(light: Color(rgb: 0x65655D), dark: Color(rgb: 0xA3A3A3))
    static let lgTextTertiary = Color.adaptive(light: Color(rgb: 0x8E8E84), dark: Color(rgb: 0x757575))

    /// Bright brand green (or the user's chosen accent — see `LgAccentPreference`) —
    /// used where it fills a shape (buttons, progress, toggle), always paired with
    /// dark text/icons on top. A computed `var`, not `let`: re-reads the current
    /// preference on every access so a change in Settings takes effect immediately.
    static var lgAccent: Color {
        Color.adaptive(light: LgAccentPreference.fill(dark: false), dark: LgAccentPreference.fill(dark: true))
    }
    /// Same accent hue, tuned darker for legibility when used AS text/icon/border color
    /// directly against the background (eyebrow labels, badges, tinted buttons).
    static var lgAccentText: Color {
        Color.adaptive(light: LgAccentPreference.text(dark: false), dark: LgAccentPreference.text(dark: true))
    }
    /// A light, uniform wash of the accent color — used for containers that should
    /// read as individually-distinct records (e.g. Inventory rows) rather than
    /// blending into the page background.
    static var lgAccentWash: Color {
        Color.adaptive(light: LgAccentPreference.fill(dark: false).opacity(0.07), dark: LgAccentPreference.fill(dark: true).opacity(0.10))
    }
    /// Edge for an `lgAccentWash` container — a stronger tint of the same accent.
    static var lgAccentWashBorder: Color {
        Color.adaptive(light: LgAccentPreference.fill(dark: false).opacity(0.24), dark: LgAccentPreference.fill(dark: true).opacity(0.26))
    }

    static let lgWarning = Color.adaptive(light: Color(rgb: 0xA44100), dark: Color(rgb: 0xEF852E))
    static let lgDanger = Color.adaptive(light: Color(rgb: 0xBB061E), dark: Color(rgb: 0xF4514F))
    static let lgInfo = Color.adaptive(light: Color(rgb: 0x2B6991), dark: Color(rgb: 0x89A9C1))

    /// Fixed dark content color for anything drawn on top of an `lgAccent` fill —
    /// that fill stays bright enough in both appearances that dark content always wins.
    static let lgOnAccent = Color(rgb: 0x0F0F0F)
    /// Content color for the small warning/danger fill circles: those fills are bright
    /// in dark mode (favoring dark content) but medium-toned in light mode (favoring light).
    static let lgOnStatusFill = Color.adaptive(light: .white, dark: Color(rgb: 0x0F0F0F))

    // Optic Line borders — a faint "etched" line around every field/card.
    // Neutral gray in both appearances (no warm tan tint in dark mode).
    static let lgSeparator = Color.adaptive(light: Color(rgb: 0x87877D).opacity(0.16), dark: Color(rgb: 0xC8C8C8).opacity(0.10))
    static let lgBorder = Color.adaptive(light: Color(rgb: 0x87877D).opacity(0.24), dark: Color(rgb: 0xC8C8C8).opacity(0.16))
    static let lgBorderStrong = Color.adaptive(light: Color(rgb: 0x87877D).opacity(0.32), dark: Color(rgb: 0xC8C8C8).opacity(0.24))
    static let lgDashedBorder = Color.adaptive(light: Color(rgb: 0x87877D).opacity(0.38), dark: Color(rgb: 0xC8C8C8).opacity(0.30))
}

// MARK: - Typography

extension Font {
    /// Named "mono" for its original intent (numeric/instrument readouts) —
    /// like every other font in the app, it now routes through the user's
    /// chosen family/size, so it's monospaced only while that's their pick.
    static func lgMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        LgFontPreference.font(size: size, weight: weight)
    }

    /// The small uppercase tracked label used above every screen title ("SESSION · 01").
    static var lgEyebrow: Font { LgFontPreference.font(size: 12, weight: .semibold) }

    /// Section header ("DETAILS", "STOCK ALERT", ...).
    static var lgSectionLabel: Font { LgFontPreference.font(size: 12.5, weight: .bold) }
}

extension View {
    /// Uppercase, tracked eyebrow label styling.
    func lgEyebrowStyle() -> some View {
        self.font(.lgEyebrow)
            .tracking(1.5)
            .foregroundStyle(Color.lgAccentText)
    }

    func lgSectionLabelStyle() -> some View {
        self.font(.lgSectionLabel)
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(Color.lgTextTertiary)
    }
}

// MARK: - Screen Header
// The large title block shown at the top of each tab.

struct ScreenHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory

    init(title: String, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.title = title
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(LgFontPreference.font(size: 31, weight: .bold))
                .foregroundStyle(Color.lgText)
            Spacer()
            accessory()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Color.lgBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.lgBorder).frame(height: 1) }
    }
}

// MARK: - Card container

struct LgCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(Color.lgCard)
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.lgBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Buttons

struct LgFieldButtonStyle: ButtonStyle {
    /// Greys the field out and drops its contrast — used when the control
    /// isn't actionable yet (e.g. "Select Ammo" before a firearm is chosen).
    var disabled: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(disabled ? Color.lgProgressTrack : Color.lgInput)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.lgBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(disabled ? 0.55 : (configuration.isPressed ? 0.7 : 1))
    }
}

struct LgPrimaryButtonStyle: ButtonStyle {
    var disabled: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LgFontPreference.font(size: 16.5, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(disabled ? Color.lgTextTertiary : Color.lgOnAccent)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(
                disabled
                    ? AnyShapeStyle(Color.lgProgressTrack)
                    : AnyShapeStyle(LinearGradient(colors: [Color.lgAccent.opacity(0.9), Color.lgAccent], startPoint: .top, endPoint: .bottom))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(disabled ? 1 : (configuration.isPressed ? 0.85 : 1))
    }
}

struct LgDashedButtonStyle: ButtonStyle {
    var disabled: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LgFontPreference.font(size: 15.5, weight: .semibold))
            .foregroundStyle(disabled ? Color.lgTextTertiary : Color.lgAccentText)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        disabled ? Color.lgDashedBorder : Color.lgAccentText.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
            // Disabled reads as plainly greyed-out; enabled is full-strength and
            // accent-colored, so "you can tap this now" is obvious at a glance.
            .opacity(disabled ? 0.45 : (configuration.isPressed ? 0.7 : 1))
    }
}

struct LgOutlineButtonStyle: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LgFontPreference.font(size: 15.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Text field styling
// SwiftUI's `TextFieldStyle` protocol has no supported custom-conformance API,
// so this is a plain view modifier applied directly to each TextField instead.

extension View {
    func lgTextFieldStyle() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(Color.lgText)
            .background(Color.lgInput)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.lgBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct LgFieldLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(LgFontPreference.font(size: 12.5))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(Color.lgTextSecondary)
    }
}

// MARK: - Badge / pill

struct LgBadge: View {
    let label: String
    let color: Color
    var body: some View {
        Text(label)
            .font(LgFontPreference.font(size: 11, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color, lineWidth: 1))
    }
}

struct LgFilledPill: View {
    let label: String
    let color: Color
    var body: some View {
        Text(label)
            .font(LgFontPreference.font(size: 12, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Progress bar

struct LgProgressBar: View {
    let percent: Double
    let color: Color
    var trackColor: Color = .lgProgressTrack
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2).fill(trackColor)
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Sheet chrome
// Every modal in the design shares this header row: a left action, a centered
// title, and an optional right action. Presented via the native .sheet with
// `.presentationDragIndicator(.visible)` supplying the grabber.

struct LgSheetHeader: View {
    let title: String
    let leftLabel: String
    let leftAction: () -> Void
    var rightLabel: String? = nil
    var rightAction: (() -> Void)? = nil
    /// Optional accessibility identifiers so a caller with a look-alike header
    /// stacked behind it (a bottom sheet over a scaffold) stays addressable.
    var leftIdentifier: String? = nil
    var rightIdentifier: String? = nil

    var body: some View {
        HStack {
            Button(action: leftAction) {
                Text(leftLabel).font(LgFontPreference.font(size: 16.5)).foregroundStyle(Color.lgAccentText)
            }
            .frame(minWidth: 50, alignment: .leading)
            .accessibilityIdentifier(leftIdentifier ?? leftLabel)

            Spacer()
            Text(title)
                .font(LgFontPreference.font(size: 17, weight: .semibold))
                .foregroundStyle(Color.lgText)
                .lineLimit(1)
            Spacer()

            Group {
                if let rightLabel, let rightAction {
                    Button(action: rightAction) {
                        Text(rightLabel).font(LgFontPreference.font(size: 16.5, weight: .semibold)).foregroundStyle(Color.lgAccentText)
                    }
                    .accessibilityIdentifier(rightIdentifier ?? rightLabel)
                } else {
                    Color.clear
                }
            }
            .frame(minWidth: 50, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.lgSheetBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.lgBorder).frame(height: 1) }
    }
}

/// Standard scaffold: header + scrollable body, on the sheet background.
struct LgSheetScaffold<Content: View>: View {
    let title: String
    let leftLabel: String
    let leftAction: () -> Void
    var rightLabel: String? = nil
    var rightAction: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            LgSheetHeader(title: title, leftLabel: leftLabel, leftAction: leftAction,
                          rightLabel: rightLabel, rightAction: rightAction)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    content()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .background(Color.lgSheetBackground)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.lgSheetBackground)
        .presentationCornerRadius(20)
    }
}

// MARK: - Custom bottom sheet
// Native `.sheet()` + `.presentationDetents` reserves a large, fixed "Sheet
// Grabber" accessibility region above the content on this iOS version — empirically
// confirmed to be untouchable via presentationDragIndicator/CornerRadius/frame
// modifiers or custom-vs-standard detents. A fully custom overlay sidesteps the
// native sheet's presentation system entirely, giving pixel-exact control.

private struct LgTopRoundedCorners: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath)
    }
}

extension View {
    func lgBottomSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        // The overlay's own subtree carries `.animation()`, scoped so it can
        // only ever affect the sheet's appear/disappear transition — chaining
        // it onto the whole `self.overlay{...}` composite (as an earlier
        // version of this did) wraps the BASE content in the same animation
        // transaction too, which was interfering with unrelated focus
        // transitions on sibling text fields (e.g. Rounds Fired losing
        // keyboard focus on tap).
        self.overlay {
            ZStack(alignment: .bottom) {
                if isPresented.wrappedValue {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture { isPresented.wrappedValue = false }
                        .transition(.opacity)
                    VStack(spacing: 0) {
                        Capsule()
                            .fill(Color.lgTextTertiary.opacity(0.5))
                            .frame(width: 36, height: 5)
                            .padding(.top, 8)
                            .padding(.bottom, 6)
                        content()
                    }
                    .background(Color.lgSheetBackground)
                    .clipShape(LgTopRoundedCorners(radius: 20))
                    .transition(.move(edge: .bottom))
                }
            }
            .zIndex(1000)
            .animation(.easeOut(duration: 0.22), value: isPresented.wrappedValue)
        }
    }
}

// MARK: - Search
// A magnifying-glass icon that sits alongside a screen's header buttons and,
// on tap, drops a small search box down from the top. The box binds straight
// to the same `searchText` the list already filters on; dismissing it keeps
// the filter, clearing the field removes it. The icon shows an accent state
// while a filter is active so it's obvious even with the box closed.

struct LgSearchIconButton: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button {
            haptic(.light)
            action()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(LgFontPreference.font(size: 15, weight: .semibold))
                .foregroundStyle(isActive ? Color.lgAccentText : Color.lgTextSecondary)
                .frame(width: 32, height: 32)
                .background(Color.lgInput)
                .overlay(Circle().strokeBorder(isActive ? Color.lgAccentText.opacity(0.55) : Color.lgBorderStrong, lineWidth: 1))
                .clipShape(Circle())
        }
        .accessibilityLabel(isActive ? "Search (filter active)" : "Search")
        .accessibilityIdentifier("SearchButton")
    }
}

extension View {
    func lgSearchBox(isPresented: Binding<Bool>, text: Binding<String>, prompt: String) -> some View {
        modifier(LgSearchBoxModifier(isPresented: isPresented, text: text, prompt: prompt))
    }
}

private struct LgSearchBoxModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    if isPresented {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .onTapGesture { isPresented = false }
                            .transition(.opacity)

                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(LgFontPreference.font(size: 15))
                                .foregroundStyle(Color.lgTextTertiary)
                            TextField(prompt, text: $text)
                                .font(LgFontPreference.font(size: 15.5))
                                .foregroundStyle(Color.lgText)
                                .focused($focused)
                                .submitLabel(.search)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onSubmit { isPresented = false }
                                .accessibilityIdentifier("SearchField")
                            if !text.isEmpty {
                                Button {
                                    text = ""
                                    focused = true
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(LgFontPreference.font(size: 15))
                                        .foregroundStyle(Color.lgTextTertiary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear search")
                            }
                            Button("Done") { isPresented = false }
                                .font(LgFontPreference.font(size: 14.5, weight: .semibold))
                                .foregroundStyle(Color.lgAccentText)
                                .accessibilityIdentifier("SearchBoxDone")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.lgSheetBackground)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.lgBorderStrong, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            // Focus once the box is actually in the tree — set
                            // from the outer onChange it can be dropped mid-transition.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true }
                        }
                    }
                }
                .zIndex(1200)
                .animation(.easeOut(duration: 0.2), value: isPresented)
            }
            .onChange(of: isPresented) { _, shown in
                // The box does its own tap-outside-to-dismiss, so park the
                // app-wide keyboard-dismiss recognizer while it's up.
                KeyboardDismissGesture.shared.isSuspended = shown
                if !shown { focused = false }
            }
            .onDisappear {
                // Tab switched away with the box still open — don't leave the
                // recognizer parked or a stale box to come back to.
                if isPresented { isPresented = false }
                KeyboardDismissGesture.shared.isSuspended = false
            }
    }
}

// MARK: - Selection sheet (used for "Select Firearm", "Select Ammo", "Select Category")

struct PickerOption: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let isSelected: Bool
    /// Applies this option's value and closes the sheet (matches the row's tap).
    let onSelect: () -> Void
    /// Optional secondary action shown as its own icon button alongside the
    /// row — e.g. a quick "add stock" shortcut on an ammo picker. Kept as a
    /// sibling button rather than nested inside the row's Button, since a
    /// Button nested in another Button's label doesn't reliably receive its
    /// own taps in SwiftUI.
    var quickAction: PickerQuickAction? = nil
}

struct PickerQuickAction {
    let icon: String
    let action: () -> Void
}

struct SelectionSheet: View {
    let title: String
    let options: [PickerOption]
    var emptyText: String? = nil
    let onCancel: () -> Void
    let onSave: () -> Void

    // A subtitle adds a second text line, so those rows render taller than a
    // title-only row — underestimating this starves the ScrollView of height
    // and clips/hides rows below the visible area (not just cosmetically:
    // clipped rows are also unhittable). Erring tall when any option in the
    // list carries a subtitle is safe; erring short is not.
    private var listMaxHeight: CGFloat {
        let rowHeight: CGFloat = options.contains(where: { $0.subtitle != nil }) ? 66 : 46
        return min(CGFloat(max(options.count, 1)) * rowHeight, 450)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tapping a row commits it immediately (via opt.onSelect()) and
            // closes the sheet, matching the standard picker pattern. Save
            // stays as a fallback close action — e.g. if nothing was tapped —
            // rather than a required step.
            LgSheetHeader(
                title: title, leftLabel: "Cancel", leftAction: onCancel,
                rightLabel: "Save", rightAction: onSave
            )
            if options.isEmpty {
                Text(emptyText ?? "Nothing to show.")
                    .font(LgFontPreference.font(size: 15))
                    .foregroundStyle(Color.lgTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(options) { opt in
                            HStack(spacing: 0) {
                                Button {
                                    haptic(.light)
                                    opt.onSelect()
                                    onSave()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(opt.title)
                                                .font(LgFontPreference.font(size: 16))
                                                .foregroundStyle(Color.lgText)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            if let subtitle = opt.subtitle {
                                                Text(subtitle)
                                                    .font(LgFontPreference.font(size: 14))
                                                    .foregroundStyle(Color.lgTextSecondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                            }
                                        }
                                        Spacer()
                                        if opt.isSelected {
                                            Image(systemName: "checkmark")
                                                .font(LgFontPreference.font(size: 17))
                                                .foregroundStyle(Color.lgAccentText)
                                        }
                                    }
                                    .padding(.vertical, 13)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("PickerOption")

                                if let quickAction = opt.quickAction {
                                    Button {
                                        haptic(.light)
                                        quickAction.action()
                                    } label: {
                                        Image(systemName: quickAction.icon)
                                            .font(LgFontPreference.font(size: 19))
                                            .foregroundStyle(Color.lgAccentText)
                                            .frame(width: 40, height: 40)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("PickerQuickAction")
                                }
                            }
                            .padding(.horizontal, 16)
                            Rectangle().fill(Color.lgSeparator).frame(height: 1).padding(.leading, 16)
                        }
                    }
                }
                .frame(maxHeight: listMaxHeight)
            }
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Multi-selection sheet (used for "Compatible Ammo" / "Compatible Firearms")
// A checklist variant of SelectionSheet: rows toggle on tap and the sheet stays
// open, so several items can be picked in one pass; Cancel discards, Save commits.
// Deliberately a separate type so SelectionSheet keeps its tap-commits-and-closes
// behavior untouched for the single-select pickers that rely on it.

struct MultiPickerOption: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
}

struct MultiSelectionSheet: View {
    let title: String
    let options: [MultiPickerOption]
    /// Toggled live as rows are tapped. Callers that want Cancel to revert
    /// should snapshot this before presenting and restore it in `onCancel`.
    @Binding var selection: Set<String>
    var emptyText: String? = nil
    /// Optional "create a new one" affordance shown under the list — e.g.
    /// adding a firearm without leaving the ammo sheet. Kept as its own button
    /// below the ScrollView, never nested inside a row.
    var addNewTitle: String? = nil
    var onAddNew: (() -> Void)? = nil
    let onCancel: () -> Void
    let onSave: () -> Void

    // Same reasoning as SelectionSheet: a subtitle makes a row two lines tall,
    // so underestimating starves the ScrollView and clips rows (which also
    // makes them unhittable). Err tall when any row carries a subtitle.
    private var listMaxHeight: CGFloat {
        let rowHeight: CGFloat = options.contains(where: { $0.subtitle != nil }) ? 66 : 46
        return min(CGFloat(max(options.count, 1)) * rowHeight, 420)
    }

    var body: some View {
        VStack(spacing: 0) {
            LgSheetHeader(
                title: title, leftLabel: "Cancel", leftAction: onCancel,
                rightLabel: "Save", rightAction: onSave,
                leftIdentifier: "MultiSheetCancel", rightIdentifier: "MultiSheetSave"
            )
            if options.isEmpty {
                Text(emptyText ?? "Nothing to show.")
                    .font(LgFontPreference.font(size: 15))
                    .foregroundStyle(Color.lgTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(options) { opt in
                            let isOn = selection.contains(opt.id)
                            Button {
                                haptic(.light)
                                if isOn { selection.remove(opt.id) } else { selection.insert(opt.id) }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: isOn ? "checkmark.square.fill" : "square")
                                        .font(LgFontPreference.font(size: 18))
                                        .foregroundStyle(isOn ? Color.lgAccentText : Color.lgTextTertiary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(opt.title)
                                            .font(LgFontPreference.font(size: 16))
                                            .foregroundStyle(Color.lgText)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        if let subtitle = opt.subtitle {
                                            Text(subtitle)
                                                .font(LgFontPreference.font(size: 14))
                                                .foregroundStyle(Color.lgTextSecondary)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 13)
                                .padding(.horizontal, 16)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("MultiPickerOption")
                            Rectangle().fill(Color.lgSeparator).frame(height: 1).padding(.leading, 16)
                        }
                    }
                }
                .frame(maxHeight: listMaxHeight)
            }

            if let addNewTitle, let onAddNew {
                Button(addNewTitle) {
                    haptic(.light)
                    onAddNew()
                }
                .buttonStyle(LgDashedButtonStyle())
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .accessibilityIdentifier("MultiPickerAddNew")
            }
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Segmented control

struct LgSegmentedControl<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                Button {
                    haptic(.light)
                    withAnimation(.easeInOut(duration: 0.15)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(LgFontPreference.font(size: 14.5, weight: .semibold))
                        .foregroundStyle(selection == option ? Color.lgText : Color.lgTextTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(selection == option ? Color.lgSegmentSelected : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.lgCard)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Empty state

struct LgEmptyState: View {
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(LgFontPreference.font(size: 17, weight: .semibold))
                .foregroundStyle(Color.lgText)
            if let message {
                Text(message)
                    .font(LgFontPreference.font(size: 15))
                    .foregroundStyle(Color.lgTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
    }
}
