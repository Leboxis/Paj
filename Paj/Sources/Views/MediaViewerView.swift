import SwiftUI
import AVKit
import UIKit

/// Visionneuse plein écran : balayage horizontal entre médias (TabView page),
/// zoom sur les photos, streaming vidéo via URL temporaire kdrive.
/// La fermeture se fait par une croix intégrée en haut à droite du lecteur.
struct MediaViewerView: View {
    let items: [FileItem]
    @Binding var index: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                    MediaPage(item: item)
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(9)
                    .background(Circle().fill(Color.black.opacity(0.45)))
                    .contentShape(Circle())
            }
            .padding(.trailing, 14)
            .padding(.top, 10)
            .accessibilityLabel("Fermer")
        }
        .background(Color.black.ignoresSafeArea())
    }
}

private struct MediaPage: View {
    let item: FileItem

    var body: some View {
        Group {
            if item.isVideo {
                VideoPage(item: item)
            } else {
                PhotoPage(item: item)
            }
        }
    }
}

// MARK: - Photo (aperçu haute résolution + zoom)

private struct PhotoPage: View {
    let item: FileItem

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(lastScale * value, 1), 6)
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale < 1.02 {
                                    withAnimation(.spring(duration: 0.25)) {
                                        scale = 1
                                        lastScale = 1
                                    }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(duration: 0.25)) {
                            scale = scale > 1.05 ? 1 : 2.5
                            lastScale = scale
                        }
                    }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: item.id) {
            let width = Int((UIScreen.main.bounds.width * UIScreen.main.scale).rounded())
            let key = "p_\(item.id)_\(width)"
            image = await ThumbnailStore.shared.image(forKey: key) {
                try await KDriveClient.shared.previewData(fileId: item.id, width: width)
            }
        }
    }
}

// MARK: - Vidéo (streaming AVPlayer)

private struct VideoPage: View {
    let item: FileItem

    @State private var player: AVPlayer?
    @State private var errorText: String?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                PlayerContainer(player: player)
            } else if let errorText {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        // L'audio s'arrête dès qu'on quitte la page (swipe ou fermeture).
        .onDisappear {
            player?.pause()
        }
        .task(id: item.id) {
            guard player == nil else { return }
            do {
                let url = try await KDriveClient.shared.temporaryUrl(for: item)
                guard !Task.isCancelled else { return }
                let newPlayer = AVPlayer(url: url)
                player = newPlayer
                newPlayer.play()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

private struct PlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
}
