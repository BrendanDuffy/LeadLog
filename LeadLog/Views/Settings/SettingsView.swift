import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @AppStorage("soundEffectsEnabled") private var hapticEnabled = true

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(eyebrow: "SETTINGS · 04", title: "Settings")

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("Feedback").padding(.top, 18)
                    LgCard(padding: 0) {
                        HStack {
                            Text("Haptic Feedback")
                                .font(.system(size: 16))
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

                    sectionLabel("Privacy & Storage").padding(.top, 22)
                    LgCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Storage")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.lgText)
                                Spacer()
                                LgFilledPill(label: "LOCAL ONLY", color: .lgAccentText)
                            }
                            Text("All your data — firearms, sessions, ammo, photos — is stored exclusively on this device. Nothing is sent to the cloud or any server.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.lgTextSecondary)
                                .lineSpacing(3)
                        }
                    }
                    .padding(.horizontal, 20)

                    sectionLabel("App Info").padding(.top, 22)
                    LgCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Version")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.lgText)
                                Spacer()
                                Text(appVersion)
                                    .font(.lgMono(15))
                                    .foregroundStyle(Color.lgTextSecondary)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("About")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.lgText)
                                Text("Lead Log is a range companion for responsible firearm owners. Track your sessions, manage your inventory, and stay on top of service intervals — all offline and private.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.lgTextSecondary)
                                    .lineSpacing(3)
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .lgSectionLabelStyle()
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }
}
