import SwiftUI
import UIKit

/// UIKit camera wrapper. Caller must check `isCameraAvailable` before presenting.
struct CameraImagePicker: UIViewControllerRepresentable {
    var onImage: (Data) -> Void
    var onCancel: () -> Void
    var onUnavailable: () -> Void

    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel, onUnavailable: onUnavailable)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        guard Self.isCameraAvailable else {
            // Present empty controller; coordinator reports unavailable on appear.
            DispatchQueue.main.async { onUnavailable() }
            return picker
        }
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (Data) -> Void
        let onCancel: () -> Void
        let onUnavailable: () -> Void

        init(
            onImage: @escaping (Data) -> Void,
            onCancel: @escaping () -> Void,
            onUnavailable: @escaping () -> Void
        ) {
            self.onImage = onImage
            self.onCancel = onCancel
            self.onUnavailable = onUnavailable
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            if let image, let data = image.jpegData(compressionQuality: 0.92) {
                onImage(data)
            } else {
                onCancel()
            }
        }
    }
}
