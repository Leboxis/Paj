import SwiftUI

/// Onglet Médias : grille 3 colonnes façon Photos, toutes les images et vidéos
/// du drive (recherche profonde, triées par date de modification). Miniatures
/// carrées uniformes haute qualité + sélection multiple avec barre d'actions.
struct MediaView: View {
    @StateObject private var model = FileListModel { cursor in
        try await KDriveClient.shared.mediaLibrary(cursor: cursor)
    }
    @StateObject private var selection = SelectionState()

    @State private var viewerShown = false
    @State private var viewerIndex = 0
    @State private var confirmingDeleteSelection = false
    @State private var moveTargets: [FileItem] = []
    @State private var tagItems: [FileItem] = []
    @State private var renamingItem: FileItem?
    @State private var newName = ""

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var selectedItems: [FileItem] {
        model.items.filter { selection.ids.contains($0.id) }
    }

    private var allSelected: Bool {
        !model.items.isEmpty && model.items.allSatisfy { selection.ids.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        cell(index: index, item: item)
                    }
                    if model.canLoadMore && !model.items.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .onAppear { Task { await model.loadMore() } }
                    }
                }
                .padding(2)
            }
            .navigationTitle("Médias")
            .toolbar { toolbarContent }
            .refreshable {
                if !selection.isActive { await model.refresh() }
            }
            .task { await model.loadFirstPageIfNeeded() }
            .fullScreenCover(isPresented: $viewerShown) {
                MediaViewerView(items: model.items, index: $viewerIndex)
            }
            .sheet(isPresented: Binding(get: { !moveTargets.isEmpty },
                                        set: { if !$0 { moveTargets = [] } })) {
                DirectoryPickerView { destination in
                    let targets = moveTargets
                    selection.end()
                    Task {
                        await model.performBatch(targets, label: "déplacement") {
                            try await KDriveClient.shared.move($0, to: destination)
                        }
                    }
                }
            }
            .sheet(isPresented: Binding(get: { !tagItems.isEmpty },
                                        set: { if !$0 { tagItems = [] } })) {
                TagsSheet(items: tagItems) {
                    selection.end()
                    Task { await model.refresh() }
                }
            }
            .alert("Renommer", isPresented: Binding(get: { renamingItem != nil },
                                                    set: { if !$0 { renamingItem = nil } })) {
                TextField("Nouveau nom", text: $newName)
                Button("Annuler", role: .cancel) {}
                Button("Enregistrer") {
                    if let item = renamingItem, !newName.isEmpty {
                        let name = newName
                        selection.end()
                        Task { await model.rename(item, to: name) }
                    }
                }
            } message: {
                Text(renamingItem?.name ?? "")
            }
            .alert("Supprimer \(selection.count) élément(s) ?",
                   isPresented: $confirmingDeleteSelection) {
                Button("Supprimer", role: .destructive) { deleteSelection() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Les éléments seront déplacés dans la corbeille du drive.")
            }
            .alert("Erreur", isPresented: Binding(get: { model.errorMessage != nil },
                                                  set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .overlay {
                if model.items.isEmpty && model.isLoading {
                    ProgressView()
                }
            }
            .overlay {
                if model.items.isEmpty && !model.isLoading && model.errorMessage == nil && !selection.isActive {
                    ContentUnavailableView("Aucun média", systemImage: "photo.on.rectangle.angled")
                }
            }
            .overlay {
                if model.isBatching {
                    ZStack {
                        Color(.systemBackground).opacity(0.6).ignoresSafeArea()
                        ProgressView("Opération en cours…")
                    }
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if selection.isActive {
            ToolbarItem(placement: .topBarLeading) {
                Button(allSelected ? "Aucun" : "Tout") {
                    if allSelected {
                        selection.clear()
                    } else {
                        selection.selectAll(model.items)
                    }
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(selection.isActive ? "Terminer" : "Sélectionner") {
                if selection.isActive {
                    selection.end()
                } else {
                    selection.start()
                }
            }
        }
        if selection.isActive {
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Text("\(selection.count) sélectionné\(selection.count == 1 ? "" : "s")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    SelectionActionsView(
                        selection: selection,
                        onFavorite: favoriteSelection,
                        onMove: { moveTargets = selectedItems },
                        onTags: { tagItems = selectedItems },
                        onRename: selection.count == 1 ? renameSelection : nil,
                        onDelete: { confirmingDeleteSelection = true }
                    )
                }
            }
        }
    }

    // MARK: - Cellules

    private func cell(index: Int, item: FileItem) -> some View {
        Button {
            if selection.isActive {
                selection.toggle(item)
            } else {
                viewerIndex = index
                viewerShown = true
            }
        } label: {
            ZStack {
                RemoteThumbnail(file: item, width: 400, height: 400, corner: 2)
                    .aspectRatio(1, contentMode: .fit)
                if item.isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
            .overlay(alignment: .topLeading) {
                if selection.isActive {
                    SelectionBadge(isOn: selection.contains(item))
                        .padding(4)
                }
            }
            .overlay(
                Rectangle()
                    .strokeBorder(selection.contains(item) ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { Task { await model.loadMoreIfNeeded(current: item) } }
    }

    // MARK: - Actions de sélection

    private func favoriteSelection() {
        let items = selectedItems
        let makeFavorite = !items.allSatisfy { $0.isFavorite == true }
        selection.end()
        Task {
            await model.performBatch(items, label: "favoris") {
                try await KDriveClient.shared.setFavorite($0, favorite: makeFavorite)
            }
        }
    }

    private func renameSelection() {
        guard let item = selectedItems.first else { return }
        renamingItem = item
        newName = item.name
    }

    private func deleteSelection() {
        let items = selectedItems
        confirmingDeleteSelection = false
        selection.end()
        Task {
            await model.performBatch(items, label: "suppression") {
                try await KDriveClient.shared.delete($0)
            }
        }
    }
}
