import Foundation

/// Liste de fichiers paginée par curseur, partagée par tous les onglets.
/// Le tri est appliqué côté serveur (order_by/order) : changer le tri
/// recharge la première page avec un nouveau loader.
@MainActor
final class FileListModel: ObservableObject {
    @Published var items: [FileItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isBatching = false
    @Published var errorMessage: String?

    private var cursor: String?
    private var hasMore = true
    private var loader: (String?) async throws -> Page<FileItem>

    init(loader: @escaping (String?) async throws -> Page<FileItem>) {
        self.loader = loader
    }

    var canLoadMore: Bool { hasMore && !isLoading }

    func setLoaderAndReload(_ newLoader: @escaping (String?) async throws -> Page<FileItem>) {
        loader = newLoader
        Task { await refresh() }
    }

    func loadFirstPageIfNeeded() async {
        guard items.isEmpty else { return }
        await loadMore()
    }

    func refresh() async {
        cursor = nil
        hasMore = true
        items.removeAll()
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let page = try await loader(cursor)
            items.append(contentsOf: page.data ?? [])
            cursor = page.cursor
            hasMore = page.hasMore ?? !((page.cursor ?? "").isEmpty)
        } catch {
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    /// Préchargement : déclenché quand la ligne affichée approche de la fin.
    func loadMoreIfNeeded(current: FileItem) async {
        guard canLoadMore, !items.isEmpty,
              let idx = items.firstIndex(where: { $0.id == current.id }),
              items.count - idx <= 15 else { return }
        await loadMore()
    }

    // MARK: - Mutations locales + serveur

    func toggleFavorite(_ item: FileItem) async {
        let favorite = !(item.isFavorite ?? false)
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isFavorite = favorite
        }
        do {
            try await KDriveClient.shared.setFavorite(item, favorite: favorite)
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

    // MARK: - Actions par lot

    /// Applique une opération à plusieurs éléments en parallèle, compte les
    /// échecs puis resynchronise la liste depuis le serveur.
    func performBatch(_ items: [FileItem], label: String,
                      operation: @escaping (FileItem) async throws -> Void) async {
        guard !items.isEmpty else { return }
        isBatching = true
        var failures = 0
        await withTaskGroup(of: Bool.self) { group in
            for item in items {
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
            errorMessage = "\(failures) échec(s) sur \(items.count) — \(label)."
        }
        await refresh()
    }
}
