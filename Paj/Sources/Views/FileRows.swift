import SwiftUI
import AVKit

// MARK: - Icônes SF Symbols par type

extension FileItem {
    var systemImage: String {
        if isDirectory { return "folder.fill" }
        if isTextFile { return "doc.text" }
        switch extensionType ?? "" {
        case "image": return "photo"
        case "video": return "film"
        case "audio": return "music.note"
        case "pdf": return "doc.richtext"
        case "archive": return "doc.zipper"
        case "text": return "doc.plaintext"
        case "spreadsheet": return "tablecells"
        case "presentation": return "rectangle.on.rectangle"
        case "code": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }

    var subtitle: String {
        var parts: [String] = []
        if let date = fileDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if let s = size, s > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(s), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Vignette avec cache disque + mémoire

struct RemoteThumbnail: View {
    let file: FileItem
    var width: Int = 160
    var height: Int = 160
    var corner: CGFloat = 8

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: corner)
                        .fill(Color(.systemGray5).opacity(0.5))
                    FileIcon(item: file, size: 28)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .task(id: file.id) {
            let key = "\(file.id)_\(width)x\(height)"
            image = await ThumbnailStore.shared.image(forKey: key) {
                try await KDriveClient.shared.thumbnailData(fileId: file.id, width: width, height: height)
            }
        }
    }
}

// MARK: - Icône stylée par type de fichier

struct FileIcon: View {
    let item: FileItem
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: item.systemImage)
            .font(.system(size: size * 0.9))
            .foregroundStyle(iconColor)
    }

    private var iconColor: Color {
        if item.isDirectory {
            if let hex = item.color, let c = Color(hex: hex) { return c }
            return Color(hex: "#0098FF")!
        }
        switch item.extensionType ?? "" {
        case "image": return .purple
        case "video": return .orange
        case "audio": return .pink
        case "pdf": return .red
        case "archive": return .brown
        case "spreadsheet": return .green
        case "presentation": return .orange
        case "code": return .blue
        default: return .secondary
        }
    }
}

// MARK: - Ligne de liste standard

struct FileRow: View {
    let item: FileItem
    var selecting = false

    @ObservedObject private var categoryStore = CategoryStore.shared

    var body: some View {
        HStack(spacing: 12) {
            if item.isMedia {
                RemoteThumbnail(file: item, width: 96, height: 96, corner: 6)
                    .frame(width: 44, height: 44)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5).opacity(0.4))
                    .frame(width: 44, height: 44)
                    .overlay(FileIcon(item: item, size: 24))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !item.tagIDs.isEmpty {
                HStack(spacing: 4) {
                    ForEach(item.tagIDs.prefix(3), id: \.self) { tagID in
                        Circle()
                            .fill(categoryStore.color(forCategoryID: tagID))
                            .frame(width: 8, height: 8)
                    }
                }
            }

            if item.isFavorite == true {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(Color(hex: "FFC107") ?? .yellow)
            }

            if item.isDirectory && !selecting {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Badge de sélection (mode sélection multiple)

struct SelectionBadge: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            if isOn {
                Circle()
                    .fill(Color.accentColor)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    )
            } else {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5)
            }
        }
        .frame(width: 22, height: 22)
        .background(Circle().fill(Color(.systemBackground).opacity(0.85)))
    }
}

// MARK: - Mini Player pour la prévisualisation vidéo au survol

struct MiniVideoPreviewPlayer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .none
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}

// MARK: - Cellule de grille

struct FileGridCell: View {
    let item: FileItem

    @AppStorage("videoHoverPreview") private var videoHoverPreview: Bool = true
    @ObservedObject private var categoryStore = CategoryStore.shared

    @State private var isHovered = false
    @State private var previewVideoUrl: URL?

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                if item.isVideo && videoHoverPreview && isHovered, let url = previewVideoUrl {
                    MiniVideoPreviewPlayer(url: url)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if item.isMedia {
                    RemoteThumbnail(file: item, width: 400, height: 400, corner: 8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5).opacity(0.4))
                        .overlay(FileIcon(item: item, size: 40))
                }
                if item.isVideo && (!isHovered || !videoHoverPreview || previewVideoUrl == nil) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .onHover { hovering in
                isHovered = hovering
                if hovering && item.isVideo && videoHoverPreview && previewVideoUrl == nil {
                    Task {
                        if let url = try? await KDriveClient.shared.temporaryUrl(for: item) {
                            previewVideoUrl = url
                        }
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !item.tagIDs.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(item.tagIDs.prefix(3), id: \.self) { tagID in
                            Circle()
                                .fill(categoryStore.color(forCategoryID: tagID))
                                .frame(width: 8, height: 8)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                        }
                    }
                    .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if item.isFavorite == true {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "FFC107") ?? .yellow)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .padding(5)
                }
            }
            // Hauteur de texte fixe : toutes les cartes ont exactement la
            // même taille, quel que soit le nom du fichier.
            Text(item.name)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(height: 16, alignment: .top)
        }
    }
}

// MARK: - Fiche d'un fichier ou d'un dossier

struct FileInfoSheet: View {
    let item: FileItem

    @Environment(\.dismiss) private var dismiss
    @State private var downloadUrl: URL?
    @State private var isDownloading = false
    @State private var isFetchingBrowserUrl = false
    @State private var errorMessage: String?

    @State private var dirCountInfo: DirectoryCountInfo?
    @State private var dirSizeInfo: DirectorySizeInfo?
    @State private var isLoadingDirDetails = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FileRow(item: item)
                        .listRowBackground(Color(.secondarySystemGroupedBackground))
                }

                Section("Détails") {
                    LabeledContent("Type", value: item.isDirectory ? "Dossier" : (item.mimeType ?? item.extensionType ?? "—"))

                    if item.isDirectory {
                        if let dirSize = dirSizeInfo {
                            LabeledContent("Taille du dossier", value: ByteCountFormatter.string(fromByteCount: Int64(dirSize.size), countStyle: .file))
                        } else if isLoadingDirDetails {
                            LabeledContent("Taille du dossier") { ProgressView() }
                        }

                        if let countInfo = dirCountInfo {
                            LabeledContent("Nombre d'éléments", value: "\(countInfo.count) (\(countInfo.files) fichier\(countInfo.files > 1 ? "s" : ""), \(countInfo.directories) dossier\(countInfo.directories > 1 ? "s" : ""))")
                        } else if isLoadingDirDetails {
                            LabeledContent("Nombre d'éléments") { ProgressView() }
                        }
                    } else {
                        if let size = item.size, size > 0 {
                            LabeledContent("Taille", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        }
                    }

                    if let date = item.fileDate {
                        LabeledContent("Modifié le", value: date.formatted(date: .long, time: .shortened))
                    }
                    LabeledContent("ID", value: String(item.id))
                }

                if !item.isDirectory {
                    Section {
                        Button {
                            downloadFile()
                        } label: {
                            HStack {
                                Label("Télécharger / Partager le fichier", systemImage: "square.and.arrow.down")
                                Spacer()
                                if isDownloading {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isDownloading)

                        Button {
                            openInBrowser()
                        } label: {
                            HStack {
                                Label("Ouvrir dans le navigateur", systemImage: "safari")
                                Spacer()
                                if isFetchingBrowserUrl {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isFetchingBrowserUrl)
                    } footer: {
                        Text("Télécharge le fichier sur l'appareil (Enregistrer dans Fichiers, Photos, etc.) ou l'ouvre via un lien temporaire sécurisé.")
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Fermer") { dismiss() }
            }
            .task {
                if item.isDirectory {
                    isLoadingDirDetails = true
                    async let countTask = try? KDriveClient.shared.directoryCount(fileId: item.id)
                    async let sizeTask = try? KDriveClient.shared.directorySize(fileId: item.id)
                    dirCountInfo = await countTask
                    dirSizeInfo = await sizeTask
                    isLoadingDirDetails = false
                }
            }
            .sheet(isPresented: Binding(get: { downloadUrl != nil },
                                        set: { if !$0 { downloadUrl = nil } })) {
                if let url = downloadUrl {
                    ShareSheet(activityItems: [url])
                }
            }
            .alert("Erreur", isPresented: Binding(get: { errorMessage != nil },
                                                  set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func downloadFile() {
        isDownloading = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let localURL = try await FileDownloadHelper.downloadAndPrepareLocalURL(item: item)
                downloadUrl = localURL
            } catch {
                errorMessage = "Échec du téléchargement : \(error.localizedDescription)"
            }
            isDownloading = false
        }
    }

    private func openInBrowser() {
        isFetchingBrowserUrl = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let url = try await KDriveClient.shared.temporaryUrl(for: item)
                _ = await UIApplication.shared.open(url)
            } catch {
                errorMessage = error.localizedDescription
            }
            isFetchingBrowserUrl = false
        }
    }
}
