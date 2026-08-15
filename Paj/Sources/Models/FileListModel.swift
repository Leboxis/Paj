import Foundation

/// Liste de fichiers paginée par curseur, partagée par tous les onglets.
/// Le tri est appliqué côté serveur (order_by/order) : changer le tri
/// recharge la première page avec un nouveau loader.
@MainActor
final class FileListModel: ObservableObject {
    @Published var items: [FileItem] = []
    @Published private(set) var isLoading = false
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
}
