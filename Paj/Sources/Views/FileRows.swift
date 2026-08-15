import SwiftUI

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
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        if let size = size, size > 0, !isDirectory {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        return parts.joined(separator: " — ")
    }
}

struct FileIcon: View {
    let item: FileItem
    var size: CGFloat = 26

    /// Couleur réelle du dossier dans kdrive (bleu kdrive par défaut),
    /// bleu pour les fichiers texte.
    private var iconColor: Color {
        if item.isDirectory {
            return Color(hex: item.color) ?? Color(hex: "#0098FF")!
        }
        if item.isTextFile {
            return .accentColor
        }
        return Color.secondary
    }

    var body: some View {
        Image(systemName: item.systemImage)
            .font(.system(size: size))
            .foregroundStyle(iconColor)
            .frame(width: size + 10, height: size + 10)
    }
}

// MARK: - Ligne façon app Fichiers

struct FileRow: View {
    let item: FileItem
    var selecting = false
    var subtitleText: String? = nil

    @ObservedObject private var categoryStore = CategoryStore.shared

    var body: some View {
        HStack(spacing: 10) {
            if item.isMedia {
                RemoteThumbnail(file: item, width: 132, height: 132, corner: 6)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                FileIcon(item: item)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitleText ?? item.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if item.isFavorite == true {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(Color(hex: "FFC107") ?? .yellow)
            }
            HStack(spacing: 3) {
                ForEach(item.tagIDs.prefix(4), id: \.self) { tagID in
                    Circle()
                        .fill(categoryStore.color(forCategoryID: tagID))
                        .frame(width: 7, height: 7)
                }
            }
            if item.isDirectory && !selecting {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Badge de sélection multiple

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

// MARK: - Cellule de grille

struct FileGridCell: View {
    let item: FileItem

    @ObservedObject private var categoryStore = CategoryStore.shared

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                if item.isMedia {
                    RemoteThumbnail(file: item, width: 400, height: 400, corner: 8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5).opacity(0.4))
                        .overlay(FileIcon(item: item, size: 40))
                }
                if item.isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                }
            }
            .aspectRatio(1, contentMode: .fit)
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

// MARK: - Fiche d'un fichier non média

struct FileInfoSheet: View {
    let item: FileItem

    @Environment(\.dismiss) private var dismiss
    @State private var temporaryUrl: URL?
    @State private var isFetchingUrl = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FileRow(item: item)
                        .listRowBackground(Color(.secondarySystemGroupedBackground))
                }
                Section("Détails") {
                    LabeledContent("Type", value: item.isDirectory ? "Dossier" : (item.mimeType ?? item.extensionType ?? "—"))
                    if let size = item.size, size > 0 {
                        LabeledContent("Taille", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                    if let date = item.fileDate {
                        LabeledContent("Modifié le", value: date.formatted(date: .long, time: .shortened))
                    }
                    LabeledContent("ID", value: String(item.id))
                }
                if !item.isDirectory {
                    Section {
                        Button {
                            openTemporaryUrl()
                        } label: {
                            HStack {
                                Label("Ouvrir via URL temporaire", systemImage: "safari")
                                Spacer()
                                if isFetchingUrl {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isFetchingUrl)

                        if let url = temporaryUrl {
                            ShareLink(item: url) {
                                Label("Partager le lien", systemImage: "square.and.arrow.up")
                            }
                        }
                    } footer: {
                        Text("Ouvre ou partage le fichier via un lien signé valable 1 h.")
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Fermer") { dismiss() }
            }
            .alert("Erreur", isPresented: Binding(get: { errorMessage != nil },
                                                  set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func openTemporaryUrl() {
        isFetchingUrl = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let url = try await KDriveClient.shared.temporaryUrl(for: item)
                temporaryUrl = url
                UIApplication.shared.open(url)
            } catch {
                errorMessage = error.localizedDescription
            }
            isFetchingUrl = false
        }
    }
}
