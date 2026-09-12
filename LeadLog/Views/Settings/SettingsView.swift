import SwiftUI

// MARK: - Accent color presets
// A small curated set rather than a full color wheel — deliberately avoids
// the red/amber hues already meaningful elsewhere (`lgDanger`, `lgWarning`)
// and the info blue-teal, so an accent choice never reads as a status color.

struct LgAccentPreset: Identifiable {
    let id: String
    let name: String
    /// The representative color shown in the swatch. `nil` picks the
    /// original lime accent (byte-identical to the un-customized default).
    let value: Color?

    var swatch: Color { value ?? Color(rgb: 0x4D9D00) }
}

let lgAccentPresets: [LgAccentPreset] = [
    LgAccentPreset(id: "green", name: "Green", value: nil),
    LgAccentPreset(id: "teal", name: "Teal", value: Color(rgb: 0x0E8C7A)),
    LgAccentPreset(id: "blue", name: "Blue", value: Color(rgb: 0x1B5FD1)),
    LgAccentPreset(id: "violet", name: "Violet", value: Color(rgb: 0x7A3FE0)),
    LgAccentPreset(id: "berry", name: "Berry", value: Color(rgb: 0xC93B8C)),
    LgAccentPreset(id: "red", name: "Red", value: Color(rgb: 0xE53935)),
    // A genuinely achromatic swatch (R=G=B) — LgAccentPreference leaves true
    // gray alone rather than tinting it, so this actually renders as gray.
    LgAccentPreset(id: "darkgrey", name: "Dark Grey", value: Color(rgb: 0x3C3C3C)),
    LgAccentPreset(id: "skyblue", name: "Sky Blue", value: Color(rgb: 0x29B6F6)),
    LgAccentPreset(id: "orange", name: "Orange", value: Color(rgb: 0xFB8C00)),
]

// MARK: - SettingsView

struct SettingsView: View {
    @AppStorage("soundEffectsEnabled") private var hapticEnabled = true

    @State private var selectedPresetID: String
    @State private var selectedFamily: LgFontFamily
    @State private var selectedSize: LgFontSizeOption

    init() {
        let storedHex = LgAccentPreference.userColor?.lgRGBHexValue
        let match = lgAccentPresets.first { $0.value?.lgRGBHexValue == storedHex }
        _selectedPresetID = State(initialValue: match?.id ?? "green")
        _selectedFamily = State(initialValue: LgFontPreference.family)
        _selectedSize = State(initialValue: LgFontPreference.sizeOption)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Settings")

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("Feedback").padding(.top, 18)
                    LgCard(padding: 0) {
                        HStack {
                            Text("Haptic Feedback")
                                .font(LgFontPreference.font(size: 16))
                                .foregroundStyle(Color.lgText)
                            Spacer()
                            Toggle("", isOn: $hapticEnabled)
                                .labelsHidden()
                                .tint(Color.lgAccent)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .padding(.horizontal, 20)

                    sectionLabel("Appearance").padding(.top, 22)
                    LgCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Accent Color")
                                .font(LgFontPreference.font(size: 16))
                                .foregroundStyle(Color.lgText)
                            // 9 presets don't all fit at once — scrolls
                            // horizontally rather than wrapping or shrinking.
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(lgAccentPresets) { preset in
                                        accentSwatch(preset)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    LgCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Font")
                                .font(LgFontPreference.font(size: 16))
                                .foregroundStyle(Color.lgText)
                            HStack(spacing: 10) {
                                ForEach(LgFontFamily.allCases) { family in
                                    fontFamilyButton(family)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    LgCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Text Size")
                                .font(LgFontPreference.font(size: 16))
                                .foregroundStyle(Color.lgText)
                            HStack(spacing: 10) {
                                ForEach(LgFontSizeOption.allCases) { option in
                                    fontSizeButton(option)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    sectionLabel("Privacy & Storage").padding(.top, 22)
                    LgCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Storage")
                                .font(LgFontPreference.font(size: 16))
                                .foregroundStyle(Color.lgText)
                            Text("All your data (firearms, sessions, ammo, photos) is stored exclusively on this device. Nothing is sent to the cloud or any server.")
                                .font(LgFontPreference.font(size: 14))
                                .foregroundStyle(Color.lgTextSecondary)
                                .lineSpacing(3)
                        }
                    }
                    .padding(.horizontal, 20)

                    sectionLabel("App Info").padding(.top, 22)
                    LgCard {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("About")
                                    .font(LgFontPreference.font(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.lgText)
                                Text("Lead Log is a range companion for responsible firearm owners. Track your sessions, manage your inventory, and stay on top of service intervals, all offline and private.")
                                    .font(LgFontPreference.font(size: 14))
                                    .foregroundStyle(Color.lgTextSecondary)
                                    .lineSpacing(3)
                            }
                            HStack {
                                Text("Version")
                                    .font(LgFontPreference.font(size: 16))
                                    .foregroundStyle(Color.lgText)
                                Spacer()
                                Text(appVersion)
                                    .font(.lgMono(15))
                                    .foregroundStyle(Color.lgTextSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
            .background(Color.lgBackground)
        }
        .background(Color.lgBackground)
    }

    private func accentSwatch(_ preset: LgAccentPreset) -> some View {
        let isSelected = selectedPresetID == preset.id
        return Button {
            guard !isSelected else { return }
            haptic(.light)
            selectedPresetID = preset.id
            LgAccentPreference.userColor = preset.value
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.lgText, lineWidth: isSelected ? 2 : 0)
                    .frame(width: 44, height: 44)
                Circle()
                    .fill(preset.swatch)
                    .frame(width: 36, height: 36)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(LgFontPreference.font(size: 13, weight: .bold))
                        .foregroundStyle(Color.lgOnAccent)
                }
            }
        }
        .accessibilityIdentifier("AccentPreset_\(preset.id)")
        .accessibilityLabel("Accent Color: \(preset.name)\(isSelected ? ", selected" : "")")
    }

    // These two preview labels deliberately call `.system(size:design:)`
    // directly rather than `LgFontPreference.font(...)` — each button must
    // preview *its own* family/size, not whichever one is currently active.
    private func fontFamilyButton(_ family: LgFontFamily) -> some View {
        let isSelected = selectedFamily == family
        return Button {
            guard !isSelected else { return }
            haptic(.light)
            selectedFamily = family
            LgFontPreference.family = family
        } label: {
            VStack(spacing: 4) {
                Text("Aa")
                    .font(family.font(size: 20, weight: .regular))
                    .foregroundStyle(isSelected ? Color.lgOnAccent : Color.lgText)
                Text(family.displayName)
                    .font(family.font(size: 10.5, weight: .medium))
                    .foregroundStyle(isSelected ? Color.lgOnAccent : Color.lgTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.lgAccent : Color.lgInput)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityIdentifier("FontFamily_\(family.rawValue)")
        .accessibilityLabel("Font: \(family.displayName)\(isSelected ? ", selected" : "")")
    }

    private func fontSizeButton(_ option: LgFontSizeOption) -> some View {
        let isSelected = selectedSize == option
        return Button {
            guard !isSelected else { return }
            haptic(.light)
            selectedSize = option
            LgFontPreference.sizeOption = option
        } label: {
            VStack(spacing: 4) {
                Text(option.abbreviation)
                    .font(selectedFamily.font(size: 15 * option.scale, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.lgOnAccent : Color.lgText)
                Text(option.displayName)
                    .font(selectedFamily.font(size: 10.5, weight: .medium))
                    .foregroundStyle(isSelected ? Color.lgOnAccent : Color.lgTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.lgAccent : Color.lgInput)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityIdentifier("FontSize_\(option.rawValue)")
        .accessibilityLabel("Text Size: \(option.displayName)\(isSelected ? ", selected" : "")")
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .lgSectionLabelStyle()
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }
}
