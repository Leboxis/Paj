import SwiftUI
import AVKit

// MARK: - Icônes SF Symbols par type (Style Orvian)

extension FileItem {
    var systemImage: String {
        if isDirectory { return "folder.fill" }
        if isTextFile { return "doc.text.fill" }
        switch extensionType ?? "" {
        case "image": return "photo.fill"
        case "video": return "video.fill"
        case "audio": return "music.note"
        case "pdf": return "doc.text.fill"
        case "archive": return "doc.zipper"
        case "text": return "doc.text.fill"
        case "spreadsheet": return "tablecells.fill"
        case "presentation": return "rectangle.on.rectangle.fill"
        case "code": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.text.fill"
        }
    }

    var subtitle: String {
        var parts: [String] = []
        if let s = size, s > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(s), countStyle: .file))
        } else if let date = fileDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Icône stylée par type de fichier (Couleurs & Style Orvian)

struct FileIcon: View {
    let item: FileItem
    var size: CGFloat = 36

    var body: some View {
        if item.isDirectory {
            Image(systemName: "folder.fill")
                .font(.system(size: size))
                .foregroundStyle(folderColor)
        } else {
            Image(systemName: item.systemImage)
                .font(.system(size: size))
                .foregroundStyle(iconColor)
        }
    }

    private var folderColor: Color {
        if let hex = item.color, let c = Color(hex: hex) {
            return c
        }
        // Orvian folder color: #FBBF24 (warm amber yellow)
        return Color(hex: "#FBBF24") ?? .yellow
    }

    private var iconColor: Color {
        // Couleurs exactes Orvian:
        // - Image: #34D399 (emerald green)
        // - Video: #60A5FA (sky blue)
        // - Text / Document: #94A3B8 (slate gray)
        // - Audio: #F472B6 (pink)
        // - Code: #38BDF8 (cyan blue)
        // - Archive: #F59E0B (amber)
        // - PDF: #EF4444 (red)
        switch item.extensionType ?? "" {
        case "image": return Color(hex: "#34D399") ?? .green
        case "video": return Color(hex: "#60A5FA") ?? .blue
        case "audio": return Color(hex: "#F472B6") ?? .pink
        case "pdf": return Color(hex: "#EF4444") ?? .red
        case "archive": return Color(hex: "#F59E0B") ?? .orange
        case "spreadsheet": return Color(hex: "#10B981") ?? .green
        case "presentation": return Color(hex: "#F59E0B") ?? .orange
        case "code": return Color(hex: "#38BDF8") ?? .cyan
        case "text": return Color(hex: "#94A3B8") ?? .gray
        default:
            if item.isTextFile { return Color(hex: "#94A3B8") ?? .gray }
            return Color(hex: "#94A3B8") ?? .secondary
        }
    }
}

// MARK: - Ligne de liste standard

struct FileRow: View {
    let item: FileItem
    var subtitleText: String? = nil
    var selecting = false

    @ObservedObject private var categoryStore = CategoryStore.shared

    var body: some View {
        HStack(spacing: 14) {
            if item.isMedia {
                RemoteThumbnail(file: item, width: 100, height: 100, corner: 8)
                    .frame(width: 44, height: 44)
            } else {
                FileIcon(item: item, size: 28)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitleText ?? item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#7F8AA0") ?? .secondary)
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
                    .foregroundStyle(Color(hex: "#FBBF24") ?? .yellow)
            }

            if item.isDirectory && !selecting {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.vertical, 3)
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

// MARK: - Cellule de grille (carte style Orvian)

struct FileGridCell: View {
    let item: FileItem

    @ObservedObject private var categoryStore = CategoryStore.shared
    @ObservedObject private var videoStore = VideoMetadataStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if item.isMedia {
                    RemoteThumbnail(file: item, width: 400, height: 400, corner: 10)
                        .aspectRatio(4/3, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    // Pas de fond gris derrière l'icône de dossier ou fichier (exactement comme Orvian)
                    FileIcon(item: item, size: item.isDirectory ? 48 : 44)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .aspectRatio(4/3, contentMode: .fit)
                }

                if item.isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(4/3, contentMode: .fit)
            .overlay(alignment: .bottomTrailing) {
                if item.isVideo, let duration = videoStore.formattedDuration(for: item.id) {
                    HStack(spacing: 3) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 7, weight: .bold))
                        Text(duration)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.65)))
                    .padding(5)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !item.tagIDs.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(item.tagIDs.prefix(3), id: \.self) { tagID in
                            Circle()
                                .fill(categoryStore.color(forCategoryID: tagID))
                                .frame(width: 8, height: 8)
                                .overlay(Circle().strokeBorder(Color.white, lineWidth: 1))
                        }
                    }
                    .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if item.isFavorite == true {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: "#FBBF24") ?? .yellow)
                        .shadow(color: Color.black.opacity(0.7), radius: 3, x: 0, y: 1)
                        .padding(6)
                }
            }
            .task {
                if item.isVideo {
                    videoStore.loadMetadata(for: item)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "#7F8AA0") ?? .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
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
