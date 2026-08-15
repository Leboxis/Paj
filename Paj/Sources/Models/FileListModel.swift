import Foundation

/// Liste de fichiers paginée par curseur, partagée par tous les onglets.
/// Concurrency : `isLoading` est posé de façon synchrone (pas de double
/// chargement), remis à zéro par `defer` (jamais coincé après une
/// annulation), et le refresh annule proprement le chargement en cours
/// puis attend la fin du nouveau.
@MainActor
final class FileListModel: ObservableObject {
    @Published var items: [FileItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isBatching = false
    @Published var errorMessage: String?

    private var cursor: String?
    private var hasMore = true
    private var loader: (String?) async throws -> Page<FileItem>
    private var filterPredicate: ((FileItem) -> Bool)?
    private var loadTask: Task<Void, Never>?

    init(loader: @escaping (String?) async throws -> Page<FileItem>) {
        self.loader = loader
    }

    var canLoadMore: Bool { hasMore && !isLoading }

    func setLoaderAndReload(_ newLoader: @escaping (String?) async throws -> Page<FileItem>,
                            filter: ((FileItem) -> Bool)? = nil) {
        loader = newLoader
        filterPredicate = filter
        Task { await refresh() }
    }

    func loadFirstPageIfNeeded() async {
        guard items.isEmpty && loadTask == nil else { return }
        await loadMore()
    }

    func refresh() async {
        loadTask?.cancel()
        isLoading = false
        cursor = nil
        hasMore = true
        items.removeAll()
        await loadMore()
        _ = await loadTask?.value
    }

    func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        loadTask = Task {
            await performLoad()
        }
    }

    private func performLoad(depth: Int = 0) async {
        defer { if depth == 0 { isLoading = false } }
        do {
            let page = try await loader(cursor)
            guard !Task.isCancelled else { return }
            var incoming = page.data ?? []
            if let filter = filterPredicate {
                incoming = incoming.filter(filter)
            }
            let existingIDs = Set(items.map(\.id))
            let uniqueIncoming = incoming.filter { !existingIDs.contains($0.id) }
            let merged = items + uniqueIncoming
            // Dossiers toujours en tête, ordre relatif conservé
            items = merged.filter { $0.isDirectory } + merged.filter { !$0.isDirectory }
            cursor = page.cursor
            hasMore = page.hasMore ?? !((page.cursor ?? "").isEmpty)

            // Si le filtre a éliminé des éléments et qu'on a moins de 10 éléments affichés alors qu'il reste des pages, on continue le chargement
            if items.count < 10 && hasMore && !(page.data ?? []).isEmpty && depth < 5 {
                await performLoad(depth: depth + 1)
            }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }


    /// Préchargement : déclenché quand la ligne affichée approche de la fin.
    func loadMoreIfNeeded(current: FileItem) async {
        guard canLoadMore, !items.isEmpty,
              let idx = items.firstIndex(where: { $0.id == current.id }),
              items.count - idx <= 15 else { return }
        await loadMore()
    }

    // MARK: - Mutations serveur

    /// Favori piloté par le serveur : appel API puis resynchronisation de la
    /// liste — aucun état local de favori dans l'app.
    func toggleFavorite(_ item: FileItem) async {
        let favorite = !(item.isFavorite ?? false)
        do {
            try await KDriveClient.shared.setFavorite(item, favorite: favorite)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ item: FileItem, to name: String) async {
        do {
            try await KDriveClient.shared.rename(item, to: name)
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx].name = name
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ item: FileItem) async {
        do {
            try await KDriveClient.shared.delete(item)
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createDirectory(name: String, in directoryId: Int) async {
        do {
            _ = try await KDriveClient.shared.createDirectory(name: name, in: directoryId)
            await refresh()
        } catch {
            errorMessage = "Impossible de créer le dossier : \(error.localizedDescription)"
        }
    }

    func uploadFile(name: String, data: Data, directoryId: Int) async {
        isBatching = true
        defer { isBatching = false }
        do {
            _ = try await KDriveClient.shared.uploadFile(name: name, data: data, directoryId: directoryId)
            await refresh()
        } catch {
            errorMessage = "Échec du téléversement : \(error.localizedDescription)"
        }
    }

    func uploadMultipleFiles(_ files: [(name: String, data: Data)], directoryId: Int) async {
        guard !files.isEmpty else { return }
        isBatching = true
        var failures = 0
        var lastError: String?
        for file in files {
            do {
                _ = try await KDriveClient.shared.uploadFile(name: file.name, data: file.data, directoryId: directoryId)
            } catch {
                failures += 1
                lastError = error.localizedDescription
            }
        }
        isBatching = false
        if failures > 0 {
            errorMessage = "\(failures) échec(s) d'importation sur \(files.count) : \(lastError ?? "erreur inconnue")"
        }
        await refresh()
    }

    // MARK: - Actions par lot

    /// Applique une opération à plusieurs éléments en parallèle, compte les
    /// échecs puis resynchronise la liste depuis le serveur.
    func performBatch(_ batch: [FileItem], label: String,
                      operation: @escaping (FileItem) async throws -> Void) async {
        guard !batch.isEmpty else { return }
        isBatching = true
        var failures = 0
        await withTaskGroup(of: Bool.self) { group in
            for item in batch {
                group.addTask {
                    do {
                        try await operation(item)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            for await ok in group where !ok {
                failures += 1
            }
        }
        isBatching = false
        if failures > 0 {
            errorMessage = "\(failures) échec(s) sur \(batch.count) — \(label)."
        }
        await refresh()
    }
}
