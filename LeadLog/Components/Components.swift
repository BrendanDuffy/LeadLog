import SwiftUI
import UIKit
import PhotosUI

// MARK: - Toast

struct ToastConfig: Equatable, Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var type: ToastType

    enum ToastType { case success, error, info }
}

struct ToastView: View {
    let config: ToastConfig
    let onDismiss: () -> Void

    private var accentColor: Color {
        switch config.type {
        case .success: return .lgAccent
        case .error:   return .lgDanger
        case .info:    return .lgInfo
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(config.title)
                    .font(LgFontPreference.font(size: 14.5, weight: .bold))
                    .foregroundStyle(Color.lgText)
                Text(config.message)
                    .font(LgFontPreference.font(size: 14))
                    .foregroundStyle(Color.lgTextSecondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 8)
            Image(systemName: "xmark")
                .font(LgFontPreference.font(size: 12.5, weight: .bold))
                .foregroundStyle(Color.lgTextTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.lgStatBlock)
        .overlay(alignment: .leading) {
            Rectangle().fill(accentColor).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { onDismiss() }
        }
    }
}

// MARK: - Photo Thumbnail
// A `scaledToFill` image reports its *intrinsic* size to layout, not the size it
// renders at, so constraining it with `.frame()` (chained, combined, or fed exact
// numbers by a GeometryReader) still leaves an element far larger than the
// visible thumbnail sitting in the hit-test tree — a portrait photo scaled to
// fill a 330pt-wide slot claims 330x440 and swallows every tap meant for the
// fields above it. Hanging the image off `Color.clear` as an overlay is what
// actually fixes that: an overlay is sized by its base and can never feed its
// own dimensions back into layout. `allowsHitTesting(false)` then guarantees the
// thumbnail is inert no matter how it resolves, since it is purely decorative —
// the surrounding controls own every interaction.

struct LgPhotoThumbnail: View {
    let image: UIImage
    let height: CGFloat
    var cornerRadius: CGFloat = 9

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(Rectangle())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Keyboard Dismissal
// Tap-outside-to-dismiss has to be a window-level UIKit recognizer. A SwiftUI
// `.onTapGesture` placed high enough to catch every outside tap also beats the
// text fields underneath it, so they never take focus at all, and moving it to a
// `.background` swings the other way — the ScrollView consumes the touch and the
// background never sees it.
//
// `cancelsTouchesInView = false` keeps every touch flowing to SwiftUI as normal.
// The recognizer then only has to decide whether the tap was meant to move focus
// somewhere else: it samples the first responder, and dismisses on the next
// runloop only if nothing else claimed focus in the meantime. That is what lets
// a tap on the Rounds Fired row focus that field instead of racing the dismissal.

@MainActor
final class KeyboardDismissGesture: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissGesture()
    private var installed = false

    /// While a control owns its own tap-outside handling (e.g. the search box
    /// overlay), suspend this window-level recognizer so it can't fight the
    /// control's auto-focus — it would otherwise read "tapped the field that's
    /// already focused" as an outside tap and resign it.
    var isSuspended = false

    func install(retriesRemaining: Int = 5) {
        guard !installed else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })
        else {
            // The key window may not exist yet on the first `onAppear`.
            guard retriesRemaining > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.install(retriesRemaining: retriesRemaining - 1)
            }
            return
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        installed = true
    }

    @objc private func handleTap() {
        guard !isSuspended else { return }
        let before = UIResponder.lgCurrentFirstResponder()
        guard before != nil else { return }
        // Let SwiftUI commit any focus change this same tap triggered before
        // deciding whether the tap really landed outside every input.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard UIResponder.lgCurrentFirstResponder() === before else { return }
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

extension UIResponder {
    private static weak var lgFoundResponder: UIResponder?

    /// `sendAction(to: nil)` routes to the first responder, so the responder
    /// itself is what records the answer.
    static func lgCurrentFirstResponder() -> UIResponder? {
        lgFoundResponder = nil
        UIApplication.shared.sendAction(#selector(lgCaptureFirstResponder), to: nil, from: nil, for: nil)
        return lgFoundResponder
    }

    @objc private func lgCaptureFirstResponder() {
        UIResponder.lgFoundResponder = self
    }
}

extension View {
    /// Enables tap-outside-to-dismiss for the keyboard, app-wide.
    func lgDismissKeyboardOnOutsideTap() -> some View {
        onAppear { KeyboardDismissGesture.shared.install() }
    }
}

// MARK: - Photo Library Picker
// SwiftUI's native `.photosPicker` modifier has a well-known bug where sibling
// controls (text fields in particular) can go unresponsive to touches after it
// dismisses. Wrapping PHPickerViewController directly, presented the same way
// CameraCaptureView presents UIImagePickerController below, sidesteps it.

struct PhotoLibraryPickerView: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                onPick(nil)
                return
            }
            provider.loadObject(ofClass: UIImage.self) { image, _ in
                DispatchQueue.main.async { self.onPick(image as? UIImage) }
            }
        }
    }
}

// MARK: - Camera Capture
// Wrapping UIImagePickerController is still the supported way to let SwiftUI
// drive the camera directly.

struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void
        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onCapture(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}

// MARK: - Image Storage

enum ImageStorageError: LocalizedError {
    case compressionFailed, writeFailed(Error)
    var errorDescription: String? {
        switch self {
        case .compressionFailed: return "Could not compress image."
        case .writeFailed(let e): return "Could not save image: \(e.localizedDescription)"
        }
    }
}

enum ImageStorage {
    @discardableResult
    static func save(_ image: UIImage, named name: String) throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw ImageStorageError.compressionFailed
        }
        let url = documentsURL.appendingPathComponent("\(name).jpg")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ImageStorageError.writeFailed(error)
        }
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
