import SwiftUI

/// Onglet Parcourir : navigation libre dans l'arborescence du drive
/// (tap sur un dossier = push, retour arrière natif).
struct BrowseView: View {
    @State private var path: [FileItem] = []

    var body: some View {
        NavigationStack(path: $path) {
            DirectoryView(directory: FileItem.root(), path: $path)
                .navigationDestination(for: FileItem.self) { directory in
                    DirectoryView(directory: directory, path: $path)
                }
        }
    }
}

struct DirectoryView: View {
    let directory: FileItem
    @Binding var path: [FileItem]

    @StateObject private var model: FileListModel

    init(directory: FileItem, path: Binding<[FileItem]>) {
        self.directory = directory
        self._path = path
        let dirId = directory.id
        _model = StateObject(wrappedValue: FileListModel { cursor in
            try await KDriveClient.shared.listDirectory(id: dirId, cursor: cursor, orderBy: "name", order: "asc")
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            if !path.isEmpty {
                BreadcrumbBar(path: path) { targetIndex in
                    if targetIndex == -1 {
                        path.removeAll()
                    } else if targetIndex < path.count - 1 {
                        path = Array(path.prefix(targetIndex + 1))
                    }
                }
            }

            FileListView(
                model: model,
                storageKey: "browse.\(directory.id)",
                currentDirectoryId: directory.id,
                onOpenDirectory: { item in path.append(item) },
                makeLoader: { orderBy, ascending in
                    { cursor in
                        try await KDriveClient.shared.listDirectory(id: directory.id,
                                                                    cursor: cursor,
                                                                    orderBy: orderBy,
                                                                    order: ascending ? "asc" : "desc")
                    }
                }
            )
        }
        .background(OrvianStyle.background)
        .navigationTitle(directory.name)
        .navigationBarTitleDisplayMode(directory.id == AppConfig.rootDirectoryId ? .large : .inline)
    }
}

/// Barre de fil d'Ariane pour naviguer rapidement dans les dossiers parents
struct BreadcrumbBar: View {
    let path: [FileItem]
    var onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                Button {
                    onSelect(-1)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "house")
                            .font(.system(size: 11))
                        Text("Accueil")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                ForEach(Array(path.enumerated()), id: \.element.id) { index, item in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(.tertiaryLabel))

                    let isLast = index == path.count - 1
                    Button {
                        if !isLast {
                            onSelect(index)
                        }
                    } label: {
                        Text(item.name)
                            .font(.system(size: 12, weight: isLast ? .bold : .medium))
                            .foregroundStyle(isLast ? Color.primary : Color.accentColor)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLast)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .background(Color(.secondarySystemGroupedBackground).opacity(0.9))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color(.separator).opacity(0.35)),
            alignment: .bottom
        )
    }
}

/// Onglet Favoris : fichiers marqués d'une étoile, tri configurable.
/// Tap sur un dossier favori = ouverture et navigation dans son contenu complet.
struct FavoritesView: View {
    @State private var path: [FileItem] = []
    @StateObject private var model = FileListModel { cursor in
        try await KDriveClient.shared.favorites(cursor: cursor, orderBy: "name", order: "asc")
    }

    var body: some View {
        NavigationStack(path: $path) {
            FileListView(
                model: model,
                storageKey: "favorites",
                onOpenDirectory: { dir in
                    path.append(dir)
                },
                makeLoader: { orderBy, ascending in
                    { cursor in
                        try await KDriveClient.shared.favorites(cursor: cursor,
                                                                orderBy: orderBy,
                                                                order: ascending ? "asc" : "desc")
                    }
                }
            )
            .navigationTitle("Favoris")
            .navigationDestination(for: FileItem.self) { directory in
                DirectoryView(directory: directory, path: $path)
            }
        }
    }
}
