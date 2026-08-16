import SwiftUI

/// Onglet Tags : affichage sous forme de grille moderne des tags du drive (catégories kdrive).
/// Tap sur un tag → affiche les fichiers associés.
struct TagsView: View {
    @State private var categories: [KCategory] = []
    @State private var searchText = ""
    @State private var loading = true
    @State private var errorText: String?
    @State private var showCreateTag = false

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
                        description: Text("Créez des tags avec le bouton + ci-dessus ou via le menu d'un fichier.")
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateTag = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Ajouter un tag")
                }
            }
            .sheet(isPresented: $showCreateTag) {
                CreateTagSheet {
                    await load(force: true)
                }
            }
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

/// Feuille de création d'un nouveau tag (catégorie kdrive) avec nom et ColorPicker synchronisé avec l'API.
struct CreateTagSheet: View {
    var onCreated: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var selectedColor: Color = Color(hex: "#FF9500") ?? .orange
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let presetPalette = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#00C7BE",
        "#007AFF", "#5856D6", "#AF52DE", "#FF2D55", "#8E8E93"
    ]

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Aperçu") {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(selectedColor)
                                .frame(width: 32, height: 32)
                            Image(systemName: "tag.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                        }

                        Text(name.trimmingCharacters(in: .whitespaces).isEmpty ? "Nom du tag" : name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(name.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .primary)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Section("Nom") {
                    TextField("Ex: Factures, Projet, Urgent…", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Couleur") {
                    ColorPicker("Couleur du tag", selection: $selectedColor, supportsOpacity: false)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Couleurs suggérées")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            ForEach(presetPalette, id: \.self) { hex in
                                Button {
                                    if let col = Color(hex: hex) {
                                        selectedColor = col
                                    }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: hex) ?? .gray)
                                            .frame(width: 28, height: 28)
                                        if selectedColor.hexString.uppercased() == hex.uppercased() {
                                            Circle()
                                                .strokeBorder(Color.primary, lineWidth: 2)
                                                .frame(width: 34, height: 34)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Nouveau tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        submit()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Ajouter")
                                .bold()
                        }
                    }
                    .disabled(!isValid || isSubmitting)
                }
            }
        }
    }

    private func submit() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil

        let hex = selectedColor.hexString

        Task { @MainActor in
            do {
                _ = try await KDriveClient.shared.createCategory(name: trimmedName, color: hex)
                await CategoryStore.shared.loadIfNeeded(force: true)
                await onCreated()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
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
