import SwiftUI
import UIKit
import AVKit

// MARK: - Icônes SF Symbols et Couleurs Orvian par type

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

    var orvianMeta: String? {
        if isDirectory { return nil }
        guard let s = size, s > 0 else { return nil }
        if s < 1024 * 1024 {
            return "\(max(1, Int(round(Double(s) / 1024.0)))) KB"
        } else {
            return String(format: "%.2f MB", Double(s) / (1024.0 * 1024.0))
        }
    }

    var subtitle: String {
        var parts: [String] = []
        if let meta = orvianMeta {
            parts.append(meta)
        }
        if let date = fileDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

// MARK: - Icône stylée par type de fichier (Palette Orvian)

struct FileIcon: View {
    let item: FileItem
    var size: CGFloat = 28

    var body: some View {
        if item.isDirectory {
            Image(systemName: "folder.fill")
                .font(.system(size: size))
                .foregroundStyle(folderColor)
                .shadow(color: folderColor.opacity(0.3), radius: 3, x: 0, y: 2)
        } else {
            Image(systemName: item.systemImage)
                .font(.system(size: size * 0.92))
                .foregroundStyle(iconColor)
                .shadow(color: iconColor.opacity(0.2), radius: 2, x: 0, y: 1)
        }
    }

    private var folderColor: Color {
        if let hex = item.color, let c = Color(hex: hex) {
            return c
        }
        return Color(hex: "#FBBF24") ?? .yellow // Orvian icon-folder: Amber Gold
    }

    private var iconColor: Color {
        switch item.extensionType ?? "" {
        case "image": return Color(hex: "#34D399") ?? .green // Orvian icon-image: Emerald Mint
        case "video": return Color(hex: "#60A5FA") ?? .blue  // Orvian icon-video: Sky Blue
        case "audio": return Color(hex: "#F472B6") ?? .pink  // Orvian icon-audio: Pink
        case "pdf": return Color(hex: "#EF4444") ?? .red     // Ruby Red
        case "archive": return Color(hex: "#A2845E") ?? .brown // Mocha Bronze
        case "spreadsheet": return Color(hex: "#34D399") ?? .green
        case "presentation": return Color(hex: "#F59E0B") ?? .orange
        case "code": return Color(hex: "#38BDF8") ?? .cyan
        default: return Color(hex: "#7F8AA0") ?? .secondary // Orvian icon-file: Slate
        }
    }
}

// MARK: - Ligne de liste (Style Orvian)

struct FileRow: View {
    let item: FileItem
    var subtitleText: String? = nil
    var selecting = false

    @ObservedObject private var categoryStore = CategoryStore.shared

    var body: some View {
        HStack(spacing: 12) {
            // Conteneur miniature / icône 50x50 sans fond lourd
            ZStack {
                if item.isMedia {
                    RemoteThumbnail(file: item, width: 140, height: 140, corner: 10)
                } else {
                    FileIcon(item: item, size: item.isDirectory ? 34 : 28)
                }

                if item.isVideo {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.black.opacity(0.65))
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.white)
                                )
                                .padding(3)
                        }
                    }
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(subtitleText ?? (item.orvianMeta ?? item.subtitle))
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#7F8AA0") ?? .secondary)

                    if !item.tagIDs.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(item.tagIDs.prefix(2), id: \.self) { tagID in
                                let cat = categoryStore.category(withID: tagID)
                                let col = categoryStore.color(forCategoryID: tagID)
                                Text(cat?.name ?? "Tag")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(col)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(col.opacity(0.16))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(col.opacity(0.38), lineWidth: 0.5))
                            }
                        }
                    }
                }
            }

            Spacer()

            if item.isFavorite == true {
                Image(systemName: "star.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "#FBBF24") ?? .yellow)
                    .shadow(color: .black.opacity(0.6), radius: 2)
            }

            if item.isDirectory && !selecting {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: "#7F8AA0") ?? Color(.tertiaryLabel))
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
                    .fill(Color(hex: "#3B82F6") ?? Color.accentColor)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    )
            } else {
                Circle()
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5)
            }
        }
        .frame(width: 22, height: 22)
        .background(Circle().fill(Color(hex: "#111827")?.opacity(0.9) ?? Color(.systemBackground)))
    }
}

// MARK: - Cellule de grille (Carte Orvian `FileCard` avec grandes miniatures et icônes épurées)

struct FileGridCell: View {
    let item: FileItem

    @ObservedObject private var categoryStore = CategoryStore.shared
    @ObservedObject private var videoStore = VideoMetadataStore.shared

    var body: some View {
        VStack(spacing: 8) {
            // Zone d'aperçu / icône sans AUCUN fond pour les dossiers/fichiers texte, et grande miniature pour les médias
            ZStack {
                if item.isMedia {
                    RemoteThumbnail(file: item, width: 600, height: 600, corner: 12)
                        .aspectRatio(4/3, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    FileIcon(item: item, size: item.isDirectory ? 72 : 62)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .aspectRatio(4/3, contentMode: .fit)
                }

                // Overlay vidéo Orvian (en bas à droite)
                if item.isVideo {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.65))
                                    .frame(width: 24, height: 24)
                                Image(systemName: "video.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(6)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(4/3, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if item.isFavorite == true {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: "#FBBF24") ?? .yellow)
                        .shadow(color: .black.opacity(0.85), radius: 3, x: 0, y: 1)
                        .padding(6)
                }
            }
            .task {
                if item.isVideo {
                    videoStore.loadMetadata(for: item)
                }
            }

            // Détails du fichier (centrés comme dans Orvian)
            VStack(spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)

                if let meta = item.orvianMeta {
                    Text(meta)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#7F8AA0") ?? .secondary)
                        .lineLimit(1)
                }

                // Badges de Tags Orvian
                if !item.tagIDs.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(item.tagIDs.prefix(2), id: \.self) { tagID in
                            let cat = categoryStore.category(withID: tagID)
                            let col = categoryStore.color(forCategoryID: tagID)
                            Text(cat?.name ?? "Tag")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(col)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(col.opacity(0.16))
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(col.opacity(0.38), lineWidth: 0.5))
                        }
                    }
                    .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "#111827")?.opacity(0.8) ?? Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 3)
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
