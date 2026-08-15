import SwiftUI

/// Onglet Tags : liste des tags du drive (catégories kdrive), tap → fichiers
/// qui portent ce tag (recherche API par id de catégorie).
struct TagsView: View {
    @State private var categories: [KCategory] = []
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .font(.footnote)
                } else if categories.isEmpty {
                    ContentUnavailableView("Aucun tag",
                                           systemImage: "tag",
                                           description: Text("Crée des tags via le menu contextuel d'un fichier (Sélectionner → Tags)."))
                }
                ForEach(categories) { category in
                    NavigationLink {
                        TagFilesView(category: category)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(category.swatch)
                                .frame(width: 14, height: 14)
                            Text(category.name)
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Tags")
            .refreshable { await load(force: true) }
            .task { await load() }
        }
    }

    private func load(force: Bool = false) async {
        if force { loading = true }
        do {
            categories = try await KDriveClient.shared.listCategories()
            await CategoryStore.shared.loadIfNeeded(force: true)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}

/// Fichiers portant un tag donné (trié par date de modification, décroissant).
struct TagFilesView: View {
    let category: KCategory

    @StateObject private var model: FileListModel

    init(category: KCategory) {
        self.category = category
        let catId = category.id
        _model = StateObject(wrappedValue: FileListModel { cursor in
            try await KDriveClient.shared.filesInCategory(catId, cursor: cursor)
        })
    }

    var body: some View {
        FileListView(
            model: model,
            storageKey: "tag.\(category.id)",
            sortable: false,
            makeLoader: { _, _ in
                { cursor in
                    try await KDriveClient.shared.filesInCategory(category.id, cursor: cursor)
                }
            }
        )
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
