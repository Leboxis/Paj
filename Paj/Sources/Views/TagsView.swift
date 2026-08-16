import SwiftUI

/// Onglet Tags : affichage sous forme de grille moderne des tags du drive (catégories kdrive).
/// Tap sur un tag → affiche les fichiers associés.
struct TagsView: View {
    @State private var categories: [KCategory] = []
    @State private var searchText = ""
    @State private var loading = true
    @State private var errorText: String?

    private var filteredCategories: [KCategory] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if loading && categories.isEmpty {
                    VStack {
                        Spacer(minLength: 40)
                        ProgressView()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if let errorText {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.red)
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Réessayer") {
                            Task { await load(force: true) }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(24)
                } else if categories.isEmpty {
                    ContentUnavailableView(
                        "Aucun tag",
                        systemImage: "tag",
                        description: Text("Créez des tags via le menu contextuel d'un fichier (Appui long → Tags).")
                    )
                    .padding(.top, 40)
                } else if filteredCategories.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredCategories) { category in
                            NavigationLink {
                                TagFilesView(category: category)
                            } label: {
                                TagCardView(category: category)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .searchable(text: $searchText, prompt: "Filtrer les tags…")
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

/// Carte de tag moderne pour la grille
struct TagCardView: View {
    let category: KCategory

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(category.swatch)
                    .frame(width: 32, height: 32)
                Image(systemName: "tag.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
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
