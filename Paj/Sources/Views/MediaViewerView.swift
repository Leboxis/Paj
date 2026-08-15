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

    @State private var shareUrl: URL?
    @State private var isSharing = false

    private var currentItem: FileItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                    MediaPage(item: item)
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Barre supérieure translucide
            HStack {
                if let item = currentItem {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .shadow(radius: 4)
                }
                Spacer()

                Button {
                    prepareAndShare()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                        .contentShape(Circle())
                }
                .padding(.trailing, 8)
                .accessibilityLabel("Partager")

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                        .contentShape(Circle())
                }
                .accessibilityLabel("Fermer")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: Binding(get: { shareUrl != nil },
                                    set: { if !$0 { shareUrl = nil } })) {
            if let url = shareUrl {
                ShareSheet(activityItems: [url])
            }
        }
    }

    private func prepareAndShare() {
        guard let item = currentItem, !isSharing else { return }
        isSharing = true
        Task { @MainActor in
            do {
                let localURL = try await FileDownloadHelper.downloadAndPrepareLocalURL(item: item)
                shareUrl = localURL
            } catch {
                if let url = try? await KDriveClient.shared.temporaryUrl(for: item) {
                    shareUrl = url
                }
            }
            isSharing = false
        }
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

// MARK: - Photo (aperçu haute résolution + zoom & pan)

private struct PhotoPage: View {
    let item: FileItem

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let newScale = lastScale * value
                                        scale = min(max(newScale, 1), 6)
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                        if scale < 1.02 {
                                            resetZoom()
                                        }
                                    },
                                DragGesture()
                                    .onChanged { value in
                                        guard scale > 1.02 else { return }
                                        let maxOffsetX = (geo.size.width * (scale - 1)) / 2
                                        let maxOffsetY = (geo.size.height * (scale - 1)) / 2
                                        let rawX = lastOffset.width + value.translation.width
                                        let rawY = lastOffset.height + value.translation.height
                                        offset = CGSize(
                                            width: min(max(rawX, -maxOffsetX), maxOffsetX),
                                            height: min(max(rawY, -maxOffsetY), maxOffsetY)
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                        )
                        .onTapGesture(count: 2) {
                            if scale > 1.05 {
                                resetZoom()
                            } else {
                                withAnimation(.spring(duration: 0.25)) {
                                    scale = 2.5
                                    lastScale = 2.5
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                        }
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .task(id: item.id) {
                let width = Int((max(geo.size.width, 390) * 3).rounded())
                let key = "p_\(item.id)_\(width)"
                image = await ThumbnailStore.shared.image(forKey: key) {
                    try await KDriveClient.shared.previewData(fileId: item.id, width: width)
                }
            }
        }
    }

    private func resetZoom() {
        withAnimation(.spring(duration: 0.25)) {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
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
