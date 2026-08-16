import SwiftUI

/// Cache des catégories (tags) du drive : l'API ne renvoie que les ids dans
/// les listes de fichiers, les noms et couleurs viennent d'ici.
@MainActor
final class CategoryStore: ObservableObject {
    static let shared = CategoryStore()

    @Published private(set) var categories: [KCategory] = []
    private var loaded = false
    private var inFlight: Task<Void, Never>?

    /// `loaded` n'est marqué vrai qu'en cas de succès : un échec réseau
    /// (token expiré, hors-ligne) sera retenté au prochain appel au lieu de
    /// laisser les pastilles de tags grises pour toute la session.
    func loadIfNeeded(force: Bool = false) async {
        if !force, let task = inFlight {
            await task.value
            return
        }
        guard !loaded || force else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            if let list = try? await KDriveClient.shared.listCategories() {
                self.categories = list
                self.loaded = true
            }
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    func category(withID id: Int) -> KCategory? {
        categories.first { $0.id == id }
    }

    func color(forCategoryID id: Int) -> Color {
        category(withID: id)?.swatch ?? Color(.systemGray)
    }
}
