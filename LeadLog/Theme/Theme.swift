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

// MARK: - Palette
// Dark values ported 1:1 from the Lead Log design (oklch → sRGB); light values are a
// matching palette in the same warm-neutral/lime-accent family, tuned for contrast.

extension Color {
    static let lgBackground = Color.adaptive(light: Color(rgb: 0xF0EEEC), dark: Color(rgb: 0x0F0D0B))
    static let lgCard = Color.adaptive(light: Color(rgb: 0xFEFDFC), dark: Color(rgb: 0x1B1815))
    static let lgCardAlt = Color.adaptive(light: Color(rgb: 0xEBE7E4), dark: Color(rgb: 0x1D1A17))
    static let lgInput = Color.adaptive(light: Color(rgb: 0xEBE7E4), dark: Color(rgb: 0x25211E))
    static let lgSheetBackground = Color.adaptive(light: Color(rgb: 0xFCFAF8), dark: Color(rgb: 0x161311))
    static let lgTabBar = Color.adaptive(light: Color(rgb: 0xF7F5F3), dark: Color(rgb: 0x14110F))
    static let lgStatBlock = Color.adaptive(light: Color(rgb: 0xEEEAE8), dark: Color(rgb: 0x221E1C))
    static let lgProgressTrack = Color.adaptive(light: Color(rgb: 0xE1DDDA), dark: Color(rgb: 0x292623))
    static let lgProgressTrackDetail = Color.adaptive(light: Color(rgb: 0xD8D3D0), dark: Color(rgb: 0x342F2C))
    static let lgSegmentSelected = Color.adaptive(light: Color(rgb: 0xFEFDFC), dark: Color(rgb: 0x312D29))

    static let lgText = Color.adaptive(light: Color(rgb: 0x0F0D0B), dark: Color(rgb: 0xF4F1EF))
    static let lgTextSecondary = Color.adaptive(light: Color(rgb: 0x504C49), dark: Color(rgb: 0xA29D9A))
    static let lgTextTertiary = Color.adaptive(light: Color(rgb: 0x7E7976), dark: Color(rgb: 0x66625F))

    /// Bright brand green — used where it fills a shape (buttons, progress, toggle),
    /// always paired with dark text/icons on top.
    static let lgAccent = Color.adaptive(light: Color(rgb: 0x4D9D00), dark: Color(rgb: 0x7FD146))
    /// Same brand hue, tuned darker for legibility when used AS text/icon/border color
    /// directly against the background (eyebrow labels, badges, tinted buttons).
    static let lgAccentText = Color.adaptive(light: Color(rgb: 0x207200), dark: Color(rgb: 0x7FD146))

    static let lgWarning = Color.adaptive(light: Color(rgb: 0xA44100), dark: Color(rgb: 0xEF852E))
    static let lgDanger = Color.adaptive(light: Color(rgb: 0xBB061E), dark: Color(rgb: 0xF4514F))
    static let lgInfo = Color.adaptive(light: Color(rgb: 0x2B6991), dark: Color(rgb: 0x89A9C1))

    /// Fixed dark content color for anything drawn on top of an `lgAccent` fill —
    /// that fill stays bright enough in both appearances that dark content always wins.
    static let lgOnAccent = Color(rgb: 0x0F0D0B)
    /// Content color for the small warning/danger fill circles: those fills are bright
    /// in dark mode (favoring dark content) but medium-toned in light mode (favoring light).
    static let lgOnStatusFill = Color.adaptive(light: .white, dark: Color(rgb: 0x0F0D0B))

    static let lgSeparator = Color.adaptive(light: .black.opacity(0.06), dark: .white.opacity(0.06))
    static let lgBorder = Color.adaptive(light: .black.opacity(0.09), dark: .white.opacity(0.08))
    static let lgBorderStrong = Color.adaptive(light: .black.opacity(0.13), dark: .white.opacity(0.1))
    static let lgDashedBorder = Color.adaptive(light: .black.opacity(0.2), dark: .white.opacity(0.18))
}

// MARK: - Typography

extension Font {
    static func lgMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// The small uppercase tracked label used above every screen title ("SESSION · 01").
    static let lgEyebrow = Font.system(size: 12, weight: .semibold, design: .monospaced)

    /// Section header ("DETAILS", "STOCK ALERT", ...).
    static let lgSectionLabel = Font.system(size: 12.5, weight: .bold)
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
// The large title block shown at the top of each tab ("SESSION · 01" / "Log Session").

struct ScreenHeader<Accessory: View>: View {
    let eyebrow: String
    let title: String
    @ViewBuilder var accessory: () -> Accessory

    init(eyebrow: String, title: String, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.eyebrow = eyebrow
        self.title = title
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow).lgEyebrowStyle()
            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .font(.system(size: 31, weight: .bold))
                    .foregroundStyle(Color.lgText)
                Spacer()
                accessory()
            }
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.lgInput)
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.lgBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct LgPrimaryButtonStyle: ButtonStyle {
    var disabled: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16.5, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(disabled ? Color.lgTextTertiary : Color.lgOnAccent)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(disabled ? Color.lgProgressTrack : Color.lgAccent)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(disabled ? 1 : (configuration.isPressed ? 0.85 : 1))
    }
}

struct LgDashedButtonStyle: ButtonStyle {
    var disabled: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15.5, weight: .semibold))
            .foregroundStyle(disabled ? Color.lgTextTertiary.opacity(0.6) : Color.lgTextSecondary)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        disabled ? Color.lgDashedBorder.opacity(0.5) : Color.lgDashedBorder,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
            .opacity(disabled ? 1 : (configuration.isPressed ? 0.7 : 1))
    }
}

struct LgOutlineButtonStyle: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15.5, weight: .semibold))
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
            .font(.system(size: 12.5))
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
            .font(.system(size: 11, weight: .bold))
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
            .font(.system(size: 12, weight: .bold))
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
    var leftColor: Color = .lgAccentText
    let leftAction: () -> Void
    var rightLabel: String? = nil
    var rightColor: Color = .lgAccentText
    var rightAction: (() -> Void)? = nil

    var body: some View {
        HStack {
            Button(action: leftAction) {
                Text(leftLabel).font(.system(size: 16.5)).foregroundStyle(leftColor)
            }
            .frame(minWidth: 50, alignment: .leading)

            Spacer()
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.lgText)
                .lineLimit(1)
            Spacer()

            Group {
                if let rightLabel, let rightAction {
                    Button(action: rightAction) {
                        Text(rightLabel).font(.system(size: 16.5, weight: .semibold)).foregroundStyle(rightColor)
                    }
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
    var leftColor: Color = .lgAccentText
    let leftAction: () -> Void
    var rightLabel: String? = nil
    var rightColor: Color = .lgAccentText
    var rightAction: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            LgSheetHeader(title: title, leftLabel: leftLabel, leftColor: leftColor, leftAction: leftAction,
                          rightLabel: rightLabel, rightColor: rightColor, rightAction: rightAction)
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

// MARK: - Selection sheet (used for both "Select Firearm" and "Select Ammo")

struct PickerOption: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let onSelect: () -> Void
}

struct SelectionSheet: View {
    let title: String
    let options: [PickerOption]
    var emptyText: String? = nil
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LgSheetHeader(title: title, leftLabel: "Cancel", leftAction: onCancel)
            if options.isEmpty {
                Text(emptyText ?? "Nothing to show.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.lgTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(options) { opt in
                            Button {
                                haptic(.light)
                                opt.onSelect()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(opt.title)
                                            .font(.system(size: 16))
                                            .foregroundStyle(Color.lgText)
                                        if let subtitle = opt.subtitle {
                                            Text(subtitle)
                                                .font(.system(size: 14))
                                                .foregroundStyle(Color.lgTextSecondary)
                                        }
                                    }
                                    Spacer()
                                    if opt.isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 17))
                                            .foregroundStyle(Color.lgAccentText)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Rectangle().fill(Color.lgSeparator).frame(height: 1).padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .background(Color.lgSheetBackground)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.lgSheetBackground)
        .presentationCornerRadius(20)
        .presentationDetents([.medium, .large])
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
                        .font(.system(size: 14.5, weight: .semibold))
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
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.lgText)
            if let message {
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.lgTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
    }
}
