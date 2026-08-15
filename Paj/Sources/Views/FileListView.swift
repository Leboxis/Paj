import SwiftUI

/// Contenu d'onglet générique : liste ou grille (bascule en toolbar), tri
/// serveur, pagination par curseur, sélection multiple avec barre d'actions
/// (favori, déplacer, tags, renommer, supprimer), visionneuse plein écran.
/// Réutilisé par Parcourir, Récents et Favoris.
struct FileListView: View {
    @ObservedObject var model: FileListModel
    var sortable = true
    var onOpenDirectory: ((FileItem) -> Void)? = nil
    var makeLoader: (_ orderBy: String, _ ascending: Bool) -> (_ cursor: String?) async throws -> Page<FileItem>

    @AppStorage private var gridView: Bool
    @AppStorage private var sortField: String
    @AppStorage private var sortAscending: Bool

    @StateObject private var selection = SelectionState()

    @State private var viewerShown = false
    @State private var viewerIndex = 0
    @State private var infoItem: FileItem?
    @State private var renamingItem: FileItem?
    @State private var newName = ""
    @State private var deletingItem: FileItem?
    @State private var confirmingDeleteSelection = false
    @State private var moveTargets: [FileItem] = []
    @State private var tagItems: [FileItem] = []

    init(model: FileListModel,
         storageKey: String,
         sortable: Bool = true,
         onOpenDirectory: ((FileItem) -> Void)? = nil,
         makeLoader: @escaping (String, Bool) -> (String?) async throws -> Page<FileItem>) {
        self.model = model
        self.sortable = sortable
        self.onOpenDirectory = onOpenDirectory
        self.makeLoader = makeLoader
        _gridView = AppStorage(wrappedValue: true, storageKey + ".isGrid")
        _sortField = AppStorage(wrappedValue: SortField.original.rawValue, storageKey + ".sortMode")
        _sortAscending = AppStorage(wrappedValue: true, storageKey + ".sortAsc")
    }

    private var selectedItems: [FileItem] {
        model.items.filter { selection.ids.contains($0.id) }
    }

    private var allSelected: Bool {
        !model.items.isEmpty && model.items.allSatisfy { selection.ids.contains($0.id) }
    }

    var body: some View {
        listContent
            .toolbar { toolbarContent }
            .refreshable { await model.refresh() }
            .task { await model.loadFirstPageIfNeeded() }
            .onChange(of: sortField) { _, _ in reloadForSort() }
            .onChange(of: sortAscending) { _, _ in reloadForSort() }
            .fullScreenCover(isPresented: $viewerShown) {
                MediaViewerView(items: model.items.filter { $0.isMedia }, index: $viewerIndex)
            }
            .sheet(item: $infoItem) { FileInfoSheet(item: $0) }
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
            .alert("Supprimer « \(deletingItem?.name ?? "") » ?",
                   isPresented: Binding(get: { deletingItem != nil },
                                        set: { if !$0 { deletingItem = nil } })) {
                Button("Supprimer", role: .destructive) {
                    if let item = deletingItem {
                        Task { await model.delete(item) }
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("L'élément sera déplacé dans la corbeille du drive.")
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
                if model.items.isEmpty && model.isLoading && model.errorMessage == nil {
                    ProgressView()
                }
            }
            .overlay {
                if model.items.isEmpty && !model.isLoading && model.errorMessage == nil && !selection.isActive {
                    ContentUnavailableView("Vide", systemImage: "tray")
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

    private func reloadForSort() {
        model.setLoaderAndReload(makeLoader(sortField, sortAscending))
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
        if !selection.isActive {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { gridView.toggle() }
                } label: {
                    Image(systemName: gridView ? "list.bullet" : "square.grid.2x2")
                }
                .accessibilityLabel(gridView ? "Vue liste" : "Vue grille")
            }
        }
        if !selection.isActive && sortable {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Trier par", selection: $sortField) {
                        ForEach(SortField.allCases) { field in
                            Text(field.label).tag(field.rawValue)
                        }
                    }
                    Picker("Ordre", selection: $sortAscending) {
                        Text("Croissant").tag(true)
                        Text("Décroissant").tag(false)
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
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

    // MARK: - Contenu

    @ViewBuilder
    private var listContent: some View {
        if gridView {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 10)], spacing: 12) {
                    ForEach(model.items) { item in
                        gridCell(item)
                    }
                }
                .padding(12)
                footer
            }
        } else {
            List {
                ForEach(model.items) { item in
                    row(item)
                }
                footer
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.isLoading && !model.items.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 8)
        } else if model.canLoadMore && !model.items.isEmpty {
            Color.clear
                .frame(height: 4)
                .onAppear { Task { await model.loadMore() } }
        }
    }

    private func row(_ item: FileItem) -> some View {
        Button {
            if selection.isActive {
                selection.toggle(item)
            } else {
                open(item)
            }
        } label: {
            HStack(spacing: 10) {
                if selection.isActive {
                    SelectionBadge(isOn: selection.contains(item))
                }
                FileRow(item: item, selecting: selection.isActive)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !selection.isActive {
                contextActions(item)
            }
        }
        .onAppear { Task { await model.loadMoreIfNeeded(current: item) } }
    }

    private func gridCell(_ item: FileItem) -> some View {
        Button {
            if selection.isActive {
                selection.toggle(item)
            } else {
                open(item)
            }
        } label: {
            FileGridCell(item: item)
                .overlay(alignment: .topLeading) {
                    if selection.isActive {
                        SelectionBadge(isOn: selection.contains(item))
                            .padding(6)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selection.contains(item) ? Color.accentColor : Color.clear, lineWidth: 3)
                )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !selection.isActive {
                contextActions(item)
            }
        }
        .onAppear { Task { await model.loadMoreIfNeeded(current: item) } }
    }

    private func open(_ item: FileItem) {
        if item.isDirectory {
            if let onOpenDirectory {
                onOpenDirectory(item)
            } else {
                infoItem = item
            }
        } else if item.isMedia {
            let media = model.items.filter { $0.isMedia }
            viewerIndex = media.firstIndex(where: { $0.id == item.id }) ?? 0
            viewerShown = true
        } else {
            infoItem = item
        }
    }

    @ViewBuilder
    private func contextActions(_ item: FileItem) -> some View {
        Button {
            Task { await model.toggleFavorite(item) }
        } label: {
            Label(item.isFavorite == true ? "Retirer des favoris" : "Ajouter aux favoris",
                  systemImage: item.isFavorite == true ? "star.slash" : "star")
        }
        Button {
            renamingItem = item
            newName = item.name
        } label: {
            Label("Renommer", systemImage: "pencil")
        }
        Button {
            moveTargets = [item]
        } label: {
            Label("Déplacer", systemImage: "folder")
        }
        Button {
            tagItems = [item]
        } label: {
            Label("Tags", systemImage: "tag")
        }
        Button(role: .destructive) {
            deletingItem = item
        } label: {
            Label("Supprimer", systemImage: "trash")
        }
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
