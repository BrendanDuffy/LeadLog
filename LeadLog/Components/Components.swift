import SwiftUI
import UIKit

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
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(Color.lgText)
                Text(config.message)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.lgTextSecondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 8)
            Image(systemName: "xmark")
                .font(.system(size: 12.5, weight: .bold))
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

// MARK: - Camera Capture
// PhotosPicker only reaches the library; wrapping UIImagePickerController is
// still the supported way to let SwiftUI drive the camera directly.

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
