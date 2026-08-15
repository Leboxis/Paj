import SwiftUI

/// Onglet Parcourir : navigation hiérarchique dans l'arborescence du drive.
struct BrowseView: View {
    @State private var path: [FileItem] = []

    var body: some View {
        NavigationStack(path: $path) {
            DirectoryView(directory: FileItem.root(), path: $path)
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
        FileListView(
            model: model,
            storageKey: "browse.\(directory.id)",
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
        .navigationTitle(directory.name)
        .navigationBarTitleDisplayMode(directory.id == AppConfig.rootDirectoryId ? .large : .inline)
    }
}

/// Onglet Récents : les derniers fichiers utilisés, tri fixé par l'API.
struct RecentsView: View {
    @StateObject private var model = FileListModel { cursor in
        try await KDriveClient.shared.recents(cursor: cursor)
    }

    var body: some View {
        NavigationStack {
            FileListView(
                model: model,
                storageKey: "recents",
                sortable: false,
                makeLoader: { _, _ in
                    { cursor in try await KDriveClient.shared.recents(cursor: cursor) }
                }
            )
            .navigationTitle("Récents")
        }
    }
}

/// Onglet Favoris : fichiers marqués d'une étoile, tri configurable.
struct FavoritesView: View {
    @StateObject private var model = FileListModel { cursor in
        try await KDriveClient.shared.favorites(cursor: cursor, orderBy: "name", order: "asc")
    }

    var body: some View {
        NavigationStack {
            FileListView(
                model: model,
                storageKey: "favorites",
                makeLoader: { orderBy, ascending in
                    { cursor in
                        try await KDriveClient.shared.favorites(cursor: cursor,
                                                                orderBy: orderBy,
                                                                order: ascending ? "asc" : "desc")
                    }
                }
            )
            .navigationTitle("Favoris")
        }
    }
}
