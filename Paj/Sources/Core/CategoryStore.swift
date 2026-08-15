import SwiftUI

/// Cache des catégories (tags) du drive : l'API ne renvoie que les ids dans
/// les listes de fichiers, les noms et couleurs viennent d'ici.
@MainActor
final class CategoryStore: ObservableObject {
    static let shared = CategoryStore()

    private(set) var categories: [KCategory] = []
    private var loaded = false

    func loadIfNeeded(force: Bool = false) async {
        guard !loaded || force else { return }
        loaded = true
        if let list = try? await KDriveClient.shared.listCategories() {
            categories = list
        }
    }

    func category(withID id: Int) -> KCategory? {
        categories.first { $0.id == id }
    }

    func color(forCategoryID id: Int) -> Color {
        category(withID: id)?.swatch ?? Color(.systemGray)
    }
}
