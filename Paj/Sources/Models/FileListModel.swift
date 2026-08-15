import Foundation

/// Liste de fichiers paginée par curseur, partagée par tous les onglets.
/// Chaque opération (loadMore, refresh) est un Task indépendant : aucun appel
/// ne bloque les autres. Le refresh annule les chargements en cours proprement.
@MainActor
final class FileListModel: ObservableObject {
    @Published var items: [FileItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isBatching = false
    @Published var errorMessage: String?

    private var cursor: String?
    private var hasMore = true
    private var loader: (String?) async throws -> Page<FileItem>
    private var loadTask: Task<Void, Never>?

    init(loader: @escaping (String?) async throws -> Page<FileItem>) {
        self.loader = loader
    }

    var canLoadMore: Bool { hasMore && !isLoading }

    func setLoaderAndReload(_ newLoader: @escaping (String?) async throws -> Page<FileItem>) {
        loader = newLoader
        refresh()
    }

    func loadFirstPageIfNeeded() {
        guard items.isEmpty && loadTask == nil else { return }
        loadMore()
    }

    func refresh() {
        loadTask?.cancel()
        loadTask = Task {
            guard !Task.isCancelled else { return }
            cursor = nil
            hasMore = true
            items.removeAll()
            await loadMore()
        }
    }

    func loadMore() {
        loadTask?.cancel()
        loadTask = Task {
            guard !Task.isCancelled else { return }
            isLoading = true
            do {
                let page = try await loader(cursor)
                guard !Task.isCancelled else { return }
                var merged = items
                merged.append(contentsOf: page.data ?? [])
                // Dossiers toujours en tête, ordre relatif conservé,
                // quel que soit le mode de tri demandé.
                items = merged.filter { $0.isDirectory } + merged.filter { !$0.isDirectory }
                cursor = page.cursor
                hasMore = page.hasMore ?? !((page.cursor ?? "").isEmpty)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    /// Préchargement : déclenché quand la ligne affichée approche de la fin.
    func loadMoreIfNeeded(current: FileItem) {
        guard canLoadMore, !items.isEmpty,
              let idx = items.firstIndex(where: { $0.id == current.id }),
              items.count - idx <= 15 else { return }
        loadMore()
    }

    // MARK: - Mutations locales + serveur

    /// Favori piloté par le serveur : appel API puis resynchronisation de la
    /// liste — aucun état local de favori dans l'app.
    func toggleFavorite(_ item: FileItem) {
        let favorite = !(item.isFavorite ?? false)
        Task {
            do {
                try await KDriveClient.shared.setFavorite(item, favorite: favorite)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func rename(_ item: FileItem, to name: String) {
        Task {
            do {
                try await KDriveClient.shared.rename(item, to: name)
                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                    items[idx].name = name
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func delete(_ item: FileItem) {
        Task {
            do {
                try await KDriveClient.shared.delete(item)
                items.removeAll { $0.id == item.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Actions par lot

    /// Applique une opération à plusieurs éléments en parallèle, compte les
    /// échecs puis resynchronise la liste depuis le serveur.
    func performBatch(_ batch: [FileItem], label: String,
                      operation: @escaping (FileItem) async throws -> Void) {
        guard !batch.isEmpty else { return }
        isBatching = true
        Task {
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
            refresh()
        }
    }
}
