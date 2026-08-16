import SwiftUI

/// Sélecteur de dossier de destination pour le déplacement d'éléments :
/// navigation dans l'arborescence (dossiers uniquement) avec bouton « Choisir ici ».
struct DirectoryPickerView: View {
    var excludedIds: Set<Int> = []
    var onPick: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path: [FileItem] = []

    var body: some View {
        NavigationStack(path: $path) {
            PickerDirectoryList(
                directory: FileItem.root(),
                path: $path,
                excludedIds: excludedIds,
                onPick: { destId in
                    onPick(destId)
                    dismiss()
                },
                onCancel: { dismiss() }
            )
            .navigationDestination(for: FileItem.self) { dir in
                PickerDirectoryList(
                    directory: dir,
                    path: $path,
                    excludedIds: excludedIds,
                    onPick: { destId in
                        onPick(destId)
                        dismiss()
                    },
                    onCancel: { dismiss() }
                )
            }
        }
    }
}

private struct PickerDirectoryList: View {
    let directory: FileItem
    @Binding var path: [FileItem]
    let excludedIds: Set<Int>
    let onPick: (Int) -> Void
    let onCancel: () -> Void

    @StateObject private var model: FileListModel

    init(directory: FileItem, path: Binding<[FileItem]>, excludedIds: Set<Int>, onPick: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.directory = directory
        self._path = path
        self.excludedIds = excludedIds
        self.onPick = onPick
        self.onCancel = onCancel
        let dirId = directory.id
        let initialModel = FileListModel { cursor in
            try await KDriveClient.shared.listDirectory(
                id: dirId,
                cursor: cursor,
                orderBy: "name",
                order: "asc"
            )
        }
        initialModel.setLoaderAndReload({ cursor in
            try await KDriveClient.shared.listDirectory(
                id: dirId,
                cursor: cursor,
                orderBy: "name",
                order: "asc"
            )
        }, filter: { $0.isDirectory })
        _model = StateObject(wrappedValue: initialModel)
    }

    var body: some View {
        List {
            if model.items.isEmpty && !model.isLoading {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Aucun sous-dossier")
                        .font(.headline)
                    Text("Appuyez sur « Choisir ici » en haut à droite pour déplacer dans « \(directory.name) ».")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .listRowBackground(Color.clear)
            } else {
                ForEach(model.items) { item in
                    let isExcluded = excludedIds.contains(item.id)
                    Button {
                        if !isExcluded {
                            path.append(item)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .font(.title3)
                                .foregroundStyle(Color(hex: item.color) ?? Color(hex: "#0098FF")!)
                            Text(item.name)
                                .font(.body)
                                .foregroundStyle(isExcluded ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if isExcluded {
                                Text("Sélectionné")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(.tertiaryLabel))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(isExcluded)
                    .buttonStyle(.plain)
                    .onAppear { Task { await model.loadMoreIfNeeded(current: item) } }
                }
            }

            if model.isLoading && model.items.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(directory.name)
        .navigationBarTitleDisplayMode(directory.id == AppConfig.rootDirectoryId ? .large : .inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Annuler") { onCancel() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Choisir ici") {
                    onPick(directory.id)
                }
                .bold()
            }
        }
        .task { await model.loadFirstPageIfNeeded() }
    }
}
