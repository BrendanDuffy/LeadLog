import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @AppStorage("soundEffectsEnabled") private var soundEffectsEnabled = true

    var body: some View {
        ZStack(alignment: .top) {
            W.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                WesternHeader(title: "Settings")
                GoldDivider()

                ScrollView {
                    VStack(spacing: 20) {
                        settingsSection(title: "AUDIO") {
                            settingsToggle(
                                label: "Sound Effects",
                                description: "Play sounds when logging sessions",
                                isOn: $soundEffectsEnabled
                            )
                        }

                        Spacer().frame(height: 32)
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.rye(12))
                .tracking(1.5)
                .foregroundStyle(W.brass.opacity(0.7))
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(W.leather.opacity(0.7))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(W.brass.opacity(0.3), lineWidth: 1))
            )
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private func settingsToggle(label: String, description: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.playfairBold(16))
                    .foregroundStyle(W.text)
                Text(description)
                    .font(.playfairRegular(13))
                    .foregroundStyle(W.muted.opacity(0.7))
            }
            Spacer()
            Toggle("", isOn: isOn)
                .tint(W.brass)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
