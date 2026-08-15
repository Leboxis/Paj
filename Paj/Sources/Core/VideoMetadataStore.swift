import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

enum VideoOrientation: String, CaseIterable, Identifiable {
    case landscape
    case portrait
    case square

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .landscape: return "rectangle"
        case .portrait: return "rectangle.portrait"
        case .square: return "square"
        }
    }
}

@MainActor
final class VideoMetadataStore: ObservableObject {
    static let shared = VideoMetadataStore()

    @Published private var durations: [Int: Double] = [:]
    @Published private var orientations: [Int: VideoOrientation] = [:]

    private var inFlight: Set<Int> = []

    func duration(for fileId: Int) -> Double? {
        durations[fileId]
    }

    func formattedDuration(for fileId: Int) -> String? {
        guard let seconds = durations[fileId], seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    func orientation(for fileId: Int) -> VideoOrientation? {
        orientations[fileId]
    }

    func register(fileId: Int, imageWidth: CGFloat, imageHeight: CGFloat) {
        guard orientations[fileId] == nil else { return }
        let ratio = imageWidth / max(imageHeight, 1)
        if ratio > 1.15 {
            orientations[fileId] = .landscape
        } else if ratio < 0.87 {
            orientations[fileId] = .portrait
        } else {
            orientations[fileId] = .square
        }
    }

    func loadMetadata(for item: FileItem) {
        guard item.isVideo else { return }
        guard durations[item.id] == nil || orientations[item.id] == nil else { return }
        guard !inFlight.contains(item.id) else { return }
        inFlight.insert(item.id)

        Task {
            defer { inFlight.remove(item.id) }
            guard let url = try? await KDriveClient.shared.temporaryUrl(for: item) else { return }
            let asset = AVURLAsset(url: url)

            if let duration = try? await asset.load(.duration) {
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite && seconds > 0 {
                    durations[item.id] = seconds
                }
            }

            if let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first {
                if let size = try? await track.load(.naturalSize) {
                    let transform = (try? await track.load(.preferredTransform)) ?? .identity
                    let transformedSize = size.applying(transform)
                    let w = abs(transformedSize.width)
                    let h = abs(transformedSize.height)
                    let ratio = w / max(h, 1)
                    if ratio > 1.15 {
                        orientations[item.id] = .landscape
                    } else if ratio < 0.87 {
                        orientations[item.id] = .portrait
                    } else {
                        orientations[item.id] = .square
                    }
                }
            }
        }
    }
}

/// Sélecteur de documents UIKit natif avec copie automatique en sandbox pour accès garanti
struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void
    var onCancel: () -> Void = {}

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .content, .data], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
