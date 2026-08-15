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
    private var loadTask: Task<Void, Never>?

    init(loader: @escaping (String?) async throws -> Page<FileItem>) {
        self.loader = loader
    }

    var canLoadMore: Bool { hasMore && !isLoading }

    func setLoaderAndReload(_ newLoader: @escaping (String?) async throws -> Page<FileItem>) {
        loader = newLoader
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
        // Attendre la fin réelle du chargement : le spinner de
        // pull-to-refresh accompagne le rechargement complet.
        _ = await loadTask?.value
    }

    func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        loadTask = Task {
            await performLoad()
        }
    }

    private func performLoad() async {
        defer { isLoading = false }
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
            await refresh()
        }
    }
}
