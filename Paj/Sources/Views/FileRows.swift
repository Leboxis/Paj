import SwiftUI

// MARK: - Icônes SF Symbols par type

extension FileItem {
    var systemImage: String {
        if isDirectory { return "folder.fill" }
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

    var body: some View {
        Image(systemName: item.systemImage)
            .font(.system(size: size))
            .foregroundStyle(item.isDirectory ? Color.accentColor : Color.secondary)
            .frame(width: size + 10, height: size + 10)
    }
}

// MARK: - Ligne façon app Fichiers

struct FileRow: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 10) {
            if item.isImage {
                RemoteThumbnail(file: item, width: 88, height: 88, corner: 6)
                    .frame(width: 44, height: 44)
            } else {
                FileIcon(item: item)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if item.isFavorite == true {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
            if item.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Cellule de grille

struct FileGridCell: View {
    let item: FileItem

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Group {
                    if item.isMedia {
                        RemoteThumbnail(file: item, width: 300, height: 300, corner: 8)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .overlay(FileIcon(item: item, size: 30))
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                if item.isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                }
            }
            Text(item.name)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Fiche d'un fichier non média

struct FileInfoSheet: View {
    let item: FileItem

    @Environment(\.dismiss) private var dismiss
    @State private var temporaryUrl: URL?

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
                            Task {
                                temporaryUrl = try? await KDriveClient.shared.temporaryUrl(for: item)
                            }
                        } label: {
                            Label("Ouvrir via URL temporaire", systemImage: "safari")
                        }
                    } footer: {
                        Text("Ouvre le fichier dans un lecteur externe via un lien signé valable 1 h.")
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Fermer") { dismiss() }
            }
            .onChange(of: temporaryUrl) { _, newValue in
                if let url = newValue {
                    UIApplication.shared.open(url)
                }
            }
        }
    }
}
