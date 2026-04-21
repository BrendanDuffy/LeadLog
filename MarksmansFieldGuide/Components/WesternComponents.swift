import SwiftUI
import PhotosUI
import UIKit

// MARK: - Corner Ornaments

/// Four gold filigree corner ornaments overlaid on a card.
struct CornerOrnaments: View {
    var size: CGFloat = 32
    var opacity: Double = 0.85

    var body: some View {
        GeometryReader { geo in
            Group {
                Image("ornament-corner")
                    .resizable().frame(width: size, height: size)
                    .position(x: size / 2 - 2, y: size / 2 - 2)
                Image("ornament-corner")
                    .resizable().frame(width: size, height: size)
                    .scaleEffect(x: -1, y: 1)
                    .position(x: geo.size.width - size / 2 + 2, y: size / 2 - 2)
                Image("ornament-corner")
                    .resizable().frame(width: size, height: size)
                    .scaleEffect(x: 1, y: -1)
                    .position(x: size / 2 - 2, y: geo.size.height - size / 2 + 2)
                Image("ornament-corner")
                    .resizable().frame(width: size, height: size)
                    .scaleEffect(x: -1, y: -1)
                    .position(x: geo.size.width - size / 2 + 2, y: geo.size.height - size / 2 + 2)
            }
            .opacity(opacity)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Brass Rivets

/// Four brass rivet images at the corners of a card.
struct BrassRivets: View {
    var size: CGFloat = 10
    var padding: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            Group {
                Image("rivet-brass").resizable().frame(width: size, height: size)
                    .position(x: padding + size / 2, y: padding + size / 2)
                Image("rivet-brass").resizable().frame(width: size, height: size)
                    .position(x: geo.size.width - padding - size / 2, y: padding + size / 2)
                Image("rivet-brass").resizable().frame(width: size, height: size)
                    .position(x: padding + size / 2, y: geo.size.height - padding - size / 2)
                Image("rivet-brass").resizable().frame(width: size, height: size)
                    .position(x: geo.size.width - padding - size / 2, y: geo.size.height - padding - size / 2)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Parchment Card Background

/// Wraps content in a parchment-textured card with brass border, corner ornaments, and rivets.
struct ParchmentCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
            CornerOrnaments()
        }
        .background(
            Image("texture-parchment")
                .resizable()
                .scaledToFill()
                .clipped()
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(W.brass, lineWidth: 2)
                .allowsHitTesting(false)
        )
    }
}

// MARK: - Parchment Display Field (tappable)

enum ParchmentIconType {
    case none, calendar, chevronDown, ammo
}

/// A read-only parchment-styled field. Pass an `onTap` closure to make it interactive.
struct ParchmentField: View {
    let label: String
    let value: String
    var iconType: ParchmentIconType = .none
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            haptic(.light)
            onTap?()
        } label: {
            ParchmentCard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.rye(17))
                            .foregroundStyle(W.textDark)
                        Text(value)
                            .font(.playfairBold(15))
                            .foregroundStyle(W.rust)
                            .lineLimit(1)
                    }
                    Spacer()
                    icon
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    @ViewBuilder
    private var icon: some View {
        switch iconType {
        case .calendar:
            Image("icon-date-calendar")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
        case .chevronDown:
            Text("▼")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(W.rust)
        case .ammo:
            Text("🔶")
                .font(.system(size: 20))
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Parchment Input Field (editable)

/// An editable text field with parchment background.
struct ParchmentInputField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default
    var isMultiline: Bool = false
    var maxLength: Int? = nil

    var body: some View {
        ParchmentCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.rye(17))
                    .foregroundStyle(W.textDark)

                if isMultiline {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .font(.playfairBold(15))
                        .foregroundStyle(W.textDark)
                        .tint(W.rust)
                        .lineLimit(2...4)
                        .onChange(of: text) { _, newValue in
                            if let max = maxLength, newValue.count > max {
                                text = String(newValue.prefix(max))
                            }
                        }
                } else {
                    TextField(placeholder, text: $text)
                        .font(.playfairBold(15))
                        .foregroundStyle(W.textDark)
                        .tint(W.rust)
                        .keyboardType(keyboardType)
                        .submitLabel(.done)
                        .onChange(of: text) { _, newValue in
                            if let max = maxLength, newValue.count > max {
                                text = String(newValue.prefix(max))
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Western Header

/// The dark leather header bar shown at the top of each tab screen.
struct WesternHeader: View {
    let title: String

    var body: some View {
        ZStack {
            W.leather

            // Title centred in the full header height
            Text(title)
                .font(.rye(22))
                .foregroundStyle(W.brass)
                .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Vignettes: top-padded, bottom-aligned so they sit on the gold divider
            HStack(spacing: 0) {
                vignetteImage(for: title, side: .left)
                Spacer()
                vignetteImage(for: title, side: .right)
            }
            .padding(.top, 10)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .offset(y: 1)
        }
        .frame(height: 88)
    }

    private enum Side { case left, right }

    @ViewBuilder
    private func vignetteImage(for title: String, side: Side) -> some View {
        let name: String = {
            switch title {
            case "Log Session":
                return side == .left ? "vignette-log-left" : "vignette-log-right"
            case "Inventory":
                return side == .left ? "vignette-inventory-left" : "vignette-inventory-right"
            case "History":
                return side == .left ? "vignette-hist-left" : "vignette-hist-right"
            case "Settings":
                return side == .left ? "vignette-settings-left" : "vignette-settings-right-v2"
            default:
                return side == .left ? "vignette-log-left" : "vignette-log-right"
            }
        }()

        // Per-tab, per-side size and padding overrides
        let height: CGFloat = 72
        let leadingPad: CGFloat = (side == .left && (title == "History" || title == "Settings")) ? 20 : 0
        let bottomPad: CGFloat = (title == "Inventory" && side == .right) ? 8 : 0

        Image(name)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .padding(.leading, leadingPad)
            .padding(.bottom, bottomPad)
    }
}

// MARK: - Gold Divider

struct GoldDivider: View {
    var body: some View {
        Rectangle()
            .fill(W.brass.opacity(0.6))
            .frame(height: 2)
    }
}

// MARK: - Western Button Label

/// Inner label for dark gradient action buttons (e.g. "+ ADD ANOTHER FIREARM")
struct WesternButtonLabel: View {
    let text: String
    var font: Font = .rye(14)

    var body: some View {
        HStack {
            Spacer()
            Text(text)
                .font(font)
                .foregroundStyle(W.brass)
                .tracking(1.2)
                .shadow(color: .black.opacity(0.8), radius: 3, y: 2)
                .padding(.vertical, 14)
            Spacer()
        }
        .padding(.horizontal, 4)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    LinearGradient(
                        colors: [W.brass.opacity(0.35), Color.black.opacity(0.5)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .padding(4)
        )
    }
}

// MARK: - Western Toast

struct ToastConfig: Equatable, Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var type: ToastType

    enum ToastType { case success, error, info }
}

struct WesternToastView: View {
    let config: ToastConfig
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if config.type == .success {
                // Western-themed success popup with popup-success image
                HStack(spacing: 14) {
                    Image("popup-success")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(config.title)
                            .font(.rye(15))
                            .foregroundStyle(W.brass)
                        Text(config.message)
                            .font(.playfairBold(13))
                            .foregroundStyle(W.text)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(W.muted)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    ZStack {
                        Image("texture-leather")
                            .resizable()
                            .scaledToFill()
                        W.leather.opacity(0.5)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(W.brass, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
            } else {
                // Simple error/info banner
                Text(config.message)
                    .font(.playfairBold(15))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(config.type == .error ? W.error : W.rust)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .onTapGesture { onDismiss() }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                onDismiss()
            }
        }
    }
}

// MARK: - No Firearms Warning

struct NoFirearmsWarning: View {
    let hasAnyFirearms: Bool

    var body: some View {
        Text(hasAnyFirearms
            ? "All your firearms are retired. Reactivate a firearm in the Inventory tab to log a new session."
            : "You have no firearms in your inventory. Please add a firearm in the Inventory tab before logging a session."
        )
        .font(.playfairRegular(15))
        .foregroundStyle(W.text)
        .lineSpacing(4)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(W.warning.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(W.warning, lineWidth: 1.5)
        )
    }
}

// MARK: - Western Tab Bar

struct WesternTabBar: View {
    @Binding var selectedTab: Int

    private let tabs: [(icon: String, label: String)] = [
        ("tabbar-icon-crosshair", "Log Session"),
        ("tabbar-icon-revolver", "Inventory"),
        ("tabbar-icon-pocketwatch", "History"),
        ("tabbar-icon-gearwrench", "Settings"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Gold divider matching the header bottom
            Rectangle()
                .fill(W.brass.opacity(0.6))
                .frame(height: 2)
            // Tab buttons
            HStack(spacing: 0) {
                ForEach(0..<tabs.count, id: \.self) { i in
                    tabButton(index: i)
                }
            }
            .frame(height: 58)
        }
        .background(W.leather)
    }

    @ViewBuilder
    private func tabButton(index: Int) -> some View {
        let tab = tabs[index]
        let isSelected = selectedTab == index

        Button {
            haptic(.light)
            selectedTab = index
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.13))
                        .padding(.horizontal, 4)
                }
                VStack(spacing: 3) {
                    Image(tab.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                        .opacity(isSelected ? 1.0 : 0.5)
                    Text(tab.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Image Storage

/// Saves/loads session and firearm photos to the app's documents directory.
enum ImageStorage {
    static func save(_ image: UIImage, named name: String) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        let url = documentsURL.appendingPathComponent("\(name).jpg")
        try? data.write(to: url, options: .atomic)
        return url.path
    }

    static func load(path: String) -> UIImage? {
        UIImage(contentsOfFile: path)
    }

    static func delete(path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
