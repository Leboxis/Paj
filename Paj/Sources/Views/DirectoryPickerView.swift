import SwiftUI

/// Sélecteur de dossier de destination pour le déplacement d'éléments :
/// navigation fluide dans l'arborescence (dossiers uniquement) avec bouton « Déplacer ici ».
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
        _model = StateObject(wrappedValue: FileListModel { cursor in
            try await KDriveClient.shared.listDirectory(
                id: dirId,
                cursor: cursor,
                orderBy: "name",
                order: "asc",
                directoriesOnly: true
            )
        })
    }

    var body: some View {
        List {
            Section {
                Button {
                    onPick(directory.id)
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundStyle(Color.accentColor)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Déplacer dans ce dossier")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            Text("Dossier actuel : « \(directory.name) »")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Sous-dossiers") {
                if model.items.isEmpty && !model.isLoading {
                    Text("Aucun sous-dossier")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(model.items) { item in
                    let isExcluded = excludedIds.contains(item.id)
                    Button {
                        if !isExcluded {
                            path.append(item)
                        }
                    } label: {
                        HStack {
                            FileRow(item: item)
                                .opacity(isExcluded ? 0.4 : 1.0)
                            if isExcluded {
                                Text("(élément sélectionné)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(isExcluded)
                    .buttonStyle(.plain)
                    .onAppear { Task { await model.loadMoreIfNeeded(current: item) } }
                }

                if model.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
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
