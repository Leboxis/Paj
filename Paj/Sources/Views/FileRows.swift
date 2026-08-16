import SwiftUI
import AVKit

// MARK: - Icônes SF Symbols alignées sur Orvian

extension FileItem {
    var systemImage: String {
        if isDirectory { return "folder" }
        if isImage { return "photo" }
        if isVideo { return "video" }
        // Orvian utilise une seule icône FileText pour les documents,
        // fichiers texte et formats non multimédias.
        return "doc.text"
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

// MARK: - Icône stylée par type de fichier (style Orvian)

struct FileIcon: View {
    let item: FileItem
    var size: CGFloat = 28

    var body: some View {
        if item.isDirectory {
            Image(systemName: "folder")
                .font(.system(size: size * 0.95))
                .foregroundStyle(folderColor)
        } else {
            Image(systemName: item.systemImage)
                .font(.system(size: size * 0.9))
                .foregroundStyle(iconColor)
        }
    }

    private var folderColor: Color {
        if let hex = item.color, let c = Color(hex: hex) {
            return c
        }
        return Color(hex: "#FBBF24") ?? .yellow
    }

    private var iconColor: Color {
        if item.isImage { return Color(hex: "#34D399") ?? .green }
        if item.isVideo { return Color(hex: "#60A5FA") ?? .blue }
        return OrvianStyle.textTertiary
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
                RemoteThumbnail(file: item, width: 100, height: 100, corner: 10)
                    .frame(width: 46, height: 46)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(OrvianStyle.tertiaryBackground.opacity(0.8))
                    .frame(width: 46, height: 46)
                    .overlay(FileIcon(item: item, size: 26))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !(subtitleText ?? item.subtitle).isEmpty {
                    Text(subtitleText ?? item.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
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

// MARK: - Cellule de grille (carte moderne)

struct FileGridCell: View {
    let item: FileItem

    @ObservedObject private var categoryStore = CategoryStore.shared
    @ObservedObject private var videoStore = VideoMetadataStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if item.isMedia {
                    RemoteThumbnail(file: item, width: 400, height: 400, corner: 10)
                } else {
                    // Les cartes Orvian laissent l'icône respirer sur la surface
                    // vitrée : aucun carré gris derrière les dossiers/documents.
                    FileIcon(item: item, size: item.isDirectory ? 48 : 44)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if item.isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                }
            }
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if item.isVideo, let duration = videoStore.formattedDuration(for: item.id) {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
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
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: "FFC107") ?? .yellow)
                        .padding(4)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                        .shadow(radius: 2)
                        .padding(5)
                }
            }
            .task {
                if item.isVideo {
                    videoStore.loadMetadata(for: item)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !item.isDirectory, let size = item.size, size > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(OrvianStyle.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OrvianStyle.border, lineWidth: 0.5)
        )
        .shadow(color: OrvianStyle.shadow, radius: 8, x: 0, y: 4)
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
