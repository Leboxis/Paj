import Foundation

/// État du mode sélection multiple d'un écran (onglet Parcourir, Médias, etc.).
@MainActor
final class SelectionState: ObservableObject {
    @Published var isActive = false
    @Published var ids: Set<Int> = []

    var count: Int { ids.count }

    func start() {
        isActive = true
        ids = []
    }

    func end() {
        isActive = false
        ids = []
    }

    func clear() {
        ids = []
    }

    func toggle(_ item: FileItem) {
        if ids.contains(item.id) {
            ids.remove(item.id)
        } else {
            ids.insert(item.id)
        }
    }

    func contains(_ item: FileItem) -> Bool {
        ids.contains(item.id)
    }

    func selectAll(_ items: [FileItem]) {
        ids = Set(items.map(\.id))
    }
}
