import MediaPlayer
import SwiftUI

/// MPMediaPickerControllerをSwiftUIから利用するためのラッパー
struct MediaPicker: UIViewControllerRepresentable {
    var onPick: (MPMediaItem) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = false
        // クラウド専用（DRM）曲は波形解析できないため、端末にダウンロード済みの曲のみ表示する
        picker.showsCloudItems = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: MPMediaPickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        private let onPick: (MPMediaItem) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping (MPMediaItem) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
            mediaPicker.dismiss(animated: true)
            if let item = mediaItemCollection.items.first {
                onPick(item)
            }
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            mediaPicker.dismiss(animated: true)
            onCancel()
        }
    }
}
