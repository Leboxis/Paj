import SwiftUI

/// Contenu d'onglet générique : liste ou grille (bascule en toolbar), tri
/// serveur, pagination par curseur, visionneuse plein écran pour les médias,
/// actions par menu contextuel. Réutilisé par Parcourir, Récents et Favoris.
struct FileListView: View {
    @ObservedObject var model: FileListModel
    var sortable = true
    var onOpenDirectory: ((FileItem) -> Void)? = nil
    var makeLoader: (_ orderBy: String, _ ascending: Bool) -> (_ cursor: String?) async throws -> Page<FileItem>

    @AppStorage private var gridView: Bool
    @AppStorage private var sortField: String
    @AppStorage private var sortAscending: Bool

    @State private var viewerShown = false
    @State private var viewerIndex = 0
    @State private var infoItem: FileItem?
    @State private var renamingItem: FileItem?
    @State private var newName = ""
    @State private var deletingItem: FileItem?

    init(model: FileListModel,
         storageKey: String,
         sortable: Bool = true,
         onOpenDirectory: ((FileItem) -> Void)? = nil,
         makeLoader: @escaping (String, Bool) -> (String?) async throws -> Page<FileItem>) {
        self.model = model
        self.sortable = sortable
        self.onOpenDirectory = onOpenDirectory
        self.makeLoader = makeLoader
        _gridView = AppStorage(wrappedValue: false, storageKey + ".gridView")
        _sortField = AppStorage(wrappedValue: SortField.name.rawValue, storageKey + ".sortField")
        _sortAscending = AppStorage(wrappedValue: true, storageKey + ".sortAscending")
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
            .alert("Renommer", isPresented: Binding(get: { renamingItem != nil },
                                                    set: { if !$0 { renamingItem = nil } })) {
                TextField("Nouveau nom", text: $newName)
                Button("Annuler", role: .cancel) {}
                Button("Enregistrer") {
                    if let item = renamingItem, !newName.isEmpty {
                        let name = newName
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
                if model.items.isEmpty && !model.isLoading && model.errorMessage == nil {
                    ContentUnavailableView("Vide", systemImage: "tray")
                }
            }
    }

    private func reloadForSort() {
        model.setLoaderAndReload(makeLoader(sortField, sortAscending))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { gridView.toggle() }
            } label: {
                Image(systemName: gridView ? "list.bullet" : "square.grid.2x2")
            }
            .accessibilityLabel(gridView ? "Vue liste" : "Vue grille")
        }
        if sortable {
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
            open(item)
        } label: {
            FileRow(item: item)
        }
        .buttonStyle(.plain)
        .contextMenu { contextActions(item) }
        .onAppear { Task { await model.loadMoreIfNeeded(current: item) } }
    }

    private func gridCell(_ item: FileItem) -> some View {
        Button {
            open(item)
        } label: {
            FileGridCell(item: item)
        }
        .buttonStyle(.plain)
        .contextMenu { contextActions(item) }
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
        Button(role: .destructive) {
            deletingItem = item
        } label: {
            Label("Supprimer", systemImage: "trash")
        }
    }
}
