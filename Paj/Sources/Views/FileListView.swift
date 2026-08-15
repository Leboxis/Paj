import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Contenu d'onglet générique : liste ou grille (bascule en toolbar), tri
/// serveur, recherche globale multi-mots, création de dossiers, import de photos/vidéos/fichiers,
/// pagination par curseur, sélection multiple avec barre d'actions
/// (favori, déplacer, tags, renommer, supprimer), visionneuse plein écran.
struct FileListView: View {
    @ObservedObject var model: FileListModel
    var sortable = true
    var currentDirectoryId: Int? = nil
    var onOpenDirectory: ((FileItem) -> Void)? = nil
    var makeLoader: (_ orderBy: String, _ ascending: Bool) -> (_ cursor: String?) async throws -> Page<FileItem>

    @AppStorage private var gridView: Bool
    @AppStorage private var sortField: String
    @AppStorage private var sortAscending: Bool
    @AppStorage("cardGridColumns") private var cardGridColumns: Int = 3

    @StateObject private var selection = SelectionState()

    @State private var searchQuery = ""
    @State private var viewerShown = false
    @State private var viewerIndex = 0
    @State private var infoItem: FileItem?
    @State private var textItem: FileItem?
    @State private var renamingItem: FileItem?
    @State private var newName = ""
    @State private var deletingItem: FileItem?
    @State private var confirmingDeleteSelection = false
    @State private var moveTargets: [FileItem] = []
    @State private var tagItems: [FileItem] = []

    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var showingPhotosPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showingFileImporter = false
    @State private var downloadFileUrl: URL?
    @State private var isDownloading = false
    @State private var isImporting = false

    init(model: FileListModel,
         storageKey: String,
         sortable: Bool = true,
         currentDirectoryId: Int? = nil,
         onOpenDirectory: ((FileItem) -> Void)? = nil,
         makeLoader: @escaping (String, Bool) -> (String?) async throws -> Page<FileItem>) {
        self.model = model
        self.sortable = sortable
        self.currentDirectoryId = currentDirectoryId
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
            .searchable(text: $searchQuery, prompt: "Rechercher sur le drive…")
            .toolbar { toolbarContent }
            .refreshable { await model.refresh() }
            .task { await model.loadFirstPageIfNeeded() }
            .onChange(of: sortField) { _, _ in reloadForSort() }
            .onChange(of: sortAscending) { _, _ in reloadForSort() }
            .onChange(of: searchQuery) { _, query in handleSearchChange(query) }
            .modifier(FileSheetsModifier(
                viewerShown: $viewerShown,
                viewerIndex: $viewerIndex,
                infoItem: $infoItem,
                textItem: $textItem,
                moveTargets: $moveTargets,
                tagItems: $tagItems,
                downloadFileUrl: $downloadFileUrl,
                model: model,
                selection: selection
            ))
            .modifier(FileAlertsModifier(
                showingNewFolder: $showingNewFolder,
                newFolderName: $newFolderName,
                renamingItem: $renamingItem,
                newName: $newName,
                deletingItem: $deletingItem,
                confirmingDeleteSelection: $confirmingDeleteSelection,
                currentDirectoryId: currentDirectoryId,
                model: model,
                selection: selection,
                deleteSelectionAction: deleteSelection
            ))
            .modifier(FileImportersModifier(
                showingPhotosPicker: $showingPhotosPicker,
                showingFileImporter: $showingFileImporter,
                selectedPhotoItems: $selectedPhotoItems,
                isImporting: $isImporting,
                currentDirectoryId: currentDirectoryId,
                model: model
            ))
            .modifier(FileOverlaysModifier(
                model: model,
                selectionActive: selection.isActive,
                searchQuery: searchQuery,
                isDownloading: isDownloading,
                isImporting: isImporting
            ))
    }

    private func handleSearchChange(_ query: String) {
        let words = query.components(separatedBy: .whitespacesAndNewlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if words.isEmpty {
            reloadForSort()
        } else {
            // Filtrage strict : tous les mots saisis doivent obligatoirement se trouver dans le titre/nom du fichier
            let filterBlock: (FileItem) -> Bool = { item in
                words.allSatisfy { word in
                    item.name.localizedCaseInsensitiveContains(word)
                }
            }
            let queryParam = words.joined(separator: " ")
            model.setLoaderAndReload({ cursor in
                try await KDriveClient.shared.searchFiles(query: queryParam, cursor: cursor)
            }, filter: filterBlock)
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
        if !selection.isActive && currentDirectoryId != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        newFolderName = ""
                        showingNewFolder = true
                    } label: {
                        Label("Nouveau dossier", systemImage: "folder.badge.plus")
                    }
                    Button {
                        showingPhotosPicker = true
                    } label: {
                        Label("Importer photos/vidéos", systemImage: "photo.badge.plus")
                    }
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Importer un fichier…", systemImage: "doc.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
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

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: max(1, cardGridColumns))
    }

    @ViewBuilder
    private var listContent: some View {
        if gridView {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 12) {
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
        } else if item.isTextFile {
            textItem = item
        } else {
            infoItem = item
        }
    }

    @ViewBuilder
    private func contextActions(_ item: FileItem) -> some View {
        Button {
            infoItem = item
        } label: {
            Label("Détails", systemImage: "info.circle")
        }

        Button {
            Task { await model.toggleFavorite(item) }
        } label: {
            Label(item.isFavorite == true ? "Retirer des favoris" : "Ajouter aux favoris",
                  systemImage: item.isFavorite == true ? "star.slash" : "star")
        }

        if !item.isDirectory {
            Button {
                downloadFile(item)
            } label: {
                Label("Télécharger", systemImage: "square.and.arrow.down")
            }
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

    private func downloadFile(_ item: FileItem) {
        isDownloading = true
        Task { @MainActor in
            do {
                let localURL = try await FileDownloadHelper.downloadAndPrepareLocalURL(item: item)
                downloadFileUrl = localURL
            } catch {
                model.errorMessage = "Échec du téléchargement : \(error.localizedDescription)"
            }
            isDownloading = false
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

// MARK: - Modificateurs décomposés

private struct FileSheetsModifier: ViewModifier {
    @Binding var viewerShown: Bool
    @Binding var viewerIndex: Int
    @Binding var infoItem: FileItem?
    @Binding var textItem: FileItem?
    @Binding var moveTargets: [FileItem]
    @Binding var tagItems: [FileItem]
    @Binding var downloadFileUrl: URL?
    @ObservedObject var model: FileListModel
    @ObservedObject var selection: SelectionState

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $viewerShown) {
                MediaViewerView(items: model.items.filter { $0.isMedia }, index: $viewerIndex)
            }
            .sheet(item: $infoItem) { FileInfoSheet(item: $0) }
            .sheet(item: $textItem) { TextFileView(item: $0) }
            .sheet(isPresented: Binding(get: { !moveTargets.isEmpty },
                                        set: { if !$0 { moveTargets = [] } })) {
                DirectoryPickerView(excludedIds: Set(moveTargets.map(\.id))) { destination in
                    let targets = moveTargets
                    moveTargets = []
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
            .sheet(isPresented: Binding(get: { downloadFileUrl != nil },
                                        set: { if !$0 { downloadFileUrl = nil } })) {
                if let url = downloadFileUrl {
                    ShareSheet(activityItems: [url])
                }
            }
    }
}

private struct FileAlertsModifier: ViewModifier {
    @Binding var showingNewFolder: Bool
    @Binding var newFolderName: String
    @Binding var renamingItem: FileItem?
    @Binding var newName: String
    @Binding var deletingItem: FileItem?
    @Binding var confirmingDeleteSelection: Bool
    var currentDirectoryId: Int?
    @ObservedObject var model: FileListModel
    @ObservedObject var selection: SelectionState
    var deleteSelectionAction: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Nouveau dossier", isPresented: $showingNewFolder) {
                TextField("Nom du dossier", text: $newFolderName)
                Button("Annuler", role: .cancel) { newFolderName = "" }
                Button("Créer") {
                    let name = newFolderName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    let dirId = currentDirectoryId ?? AppConfig.rootDirectoryId
                    newFolderName = ""
                    Task {
                        await model.createDirectory(name: name, in: dirId)
                    }
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
                Button("Supprimer", role: .destructive) { deleteSelectionAction() }
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
    }
}

private struct FileImportersModifier: ViewModifier {
    @Binding var showingPhotosPicker: Bool
    @Binding var showingFileImporter: Bool
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    @Binding var isImporting: Bool
    var currentDirectoryId: Int?
    @ObservedObject var model: FileListModel

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $showingPhotosPicker,
                selection: $selectedPhotoItems,
                matching: .any(of: [.images, .videos])
            )
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    guard !urls.isEmpty else { return }
                    isImporting = true
                    Task { @MainActor in
                        var files: [(name: String, data: Data)] = []
                        for url in urls {
                            let accessed = url.startAccessingSecurityScopedResource()
                            defer {
                                if accessed { url.stopAccessingSecurityScopedResource() }
                            }
                            if let data = try? Data(contentsOf: url) {
                                files.append((url.lastPathComponent, data))
                            } else {
                                var coordinatedData: Data?
                                let coordinator = NSFileCoordinator()
                                coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: nil) { readUrl in
                                    coordinatedData = try? Data(contentsOf: readUrl)
                                }
                                if let d = coordinatedData {
                                    files.append((url.lastPathComponent, d))
                                }
                            }
                        }
                        if !files.isEmpty {
                            let dirId = currentDirectoryId ?? AppConfig.rootDirectoryId
                            await model.uploadMultipleFiles(files, directoryId: dirId)
                        } else {
                            model.errorMessage = "Impossible de lire le ou les fichiers sélectionnés."
                        }
                        isImporting = false
                    }
                case .failure(let error):
                    model.errorMessage = "Importation impossible : \(error.localizedDescription)"
                }
            }
            .onChange(of: selectedPhotoItems) { _, items in
                guard !items.isEmpty else { return }
                isImporting = true
                Task { @MainActor in
                    var files: [(name: String, data: Data)] = []
                    for item in items {
                        do {
                            if let media = try await MediaLoader.loadMedia(from: item) {
                                files.append(media)
                            }
                        } catch {
                            // On tente les autres médias
                        }
                    }
                    if !files.isEmpty {
                        let dirId = currentDirectoryId ?? AppConfig.rootDirectoryId
                        await model.uploadMultipleFiles(files, directoryId: dirId)
                    } else {
                        model.errorMessage = "Impossible de lire les photos ou vidéos sélectionnées."
                    }
                    selectedPhotoItems = []
                    isImporting = false
                }
            }
    }
}

private struct FileOverlaysModifier: ViewModifier {
    @ObservedObject var model: FileListModel
    var selectionActive: Bool
    var searchQuery: String
    var isDownloading: Bool
    var isImporting: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if model.items.isEmpty && model.isLoading && model.errorMessage == nil {
                    ProgressView()
                }
            }
            .overlay {
                if model.items.isEmpty && !model.isLoading && model.errorMessage == nil && !selectionActive {
                    ContentUnavailableView(searchQuery.isEmpty ? "Vide" : "Aucun résultat",
                                           systemImage: searchQuery.isEmpty ? "tray" : "magnifyingglass",
                                           description: searchQuery.isEmpty ? nil : Text("Aucun fichier trouvé contenant tous les mots de « \(searchQuery) »"))
                }
            }
            .overlay {
                if model.isBatching || isImporting || isDownloading {
                    ZStack {
                        Color(.systemBackground).opacity(0.7).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(isImporting ? "Importation en cours…" : (isDownloading ? "Téléchargement en cours…" : "Opération en cours…"))
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(20)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
                        .shadow(radius: 6)
                    }
                }
            }
    }
}
