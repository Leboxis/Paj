import SwiftUI

/// Sélecteur de dossier de destination pour le déplacement de fichiers :
/// navigation dans l'arborescence (dossiers uniquement) + « Choisir ici ».
struct DirectoryPickerView: View {
    var onPick: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path: [FileItem] = []

    var body: some View {
        NavigationStack(path: $path) {
            PickerDirectoryList(directory: FileItem.root(), path: $path)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Annuler") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Choisir ici") {
                            onPick(path.last?.id ?? AppConfig.rootDirectoryId)
                            dismiss()
                        }
                        .bold()
                    }
                }
        }
    }
}

private struct PickerDirectoryList: View {
    let directory: FileItem
    @Binding var path: [FileItem]

    @StateObject private var model: FileListModel

    init(directory: FileItem, path: Binding<[FileItem]>) {
        self.directory = directory
        self._path = path
        let dirId = directory.id
        _model = StateObject(wrappedValue: FileListModel { cursor in
            try await KDriveClient.shared.listDirectory(id: dirId,
                                                        cursor: cursor,
                                                        orderBy: "name",
                                                        order: "asc",
                                                        directoriesOnly: true)
        })
    }

    var body: some View {
        List {
            ForEach(model.items) { item in
                Button {
                    path.append(item)
                } label: {
                    FileRow(item: item)
                }
                .buttonStyle(.plain)
                .onAppear { Task { await model.loadMoreIfNeeded(current: item) } }
            }
            if model.isLoading && model.items.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(directory.name)
        .navigationBarTitleDisplayMode(directory.id == AppConfig.rootDirectoryId ? .large : .inline)
        .task { await model.loadFirstPageIfNeeded() }
    }
}
