import SwiftUI

/// Gestion des tags (catégories kdrive) pour un ou plusieurs éléments :
/// appliquer/retirer un tag existant, ou créer un tag (nom + couleur) et
/// l'appliquer immédiatement. L'état coché se calcule depuis les items.
struct TagsSheet: View {
    let items: [FileItem]
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var categories: [KCategory] = []
    @State private var loading = true
    @State private var busy = false
    @State private var newName = ""
    @State private var newColor = "#FF9500"
    @State private var errorText: String?

    private let palette = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#00C7BE",
                           "#007AFF", "#5856D6", "#AF52DE", "#FF2D55", "#8E8E93"]

    private var fileIds: [Int] { items.map(\.id) }

    private func hasTag(_ category: KCategory) -> Bool {
        !items.isEmpty && items.allSatisfy { $0.categoryIDs.contains(category.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if loading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if categories.isEmpty {
                        Text("Aucun tag. Crée-en un ci-dessous.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(categories) { category in
                        Button {
                            toggle(category)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(category.swatch)
                                    .frame(width: 18, height: 18)
                                Text(category.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if hasTag(category) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .disabled(busy)
                    }
                } header: {
                    Text("Tags du drive")
                } footer: {
                    Text("Applique ou retire le tag sur \(items.count) élément(s).")
                }

                Section("Nouveau tag") {
                    TextField("Nom du tag", text: $newName)
                        .textInputAutocapitalization(.words)
                    HStack(spacing: 10) {
                        ForEach(palette, id: \.self) { hex in
                            Button {
                                newColor = hex
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: hex) ?? .gray)
                                        .frame(width: 28, height: 28)
                                    if newColor == hex {
                                        Circle()
                                            .strokeBorder(Color.primary, lineWidth: 2)
                                            .frame(width: 33, height: 33)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        createAndAssign()
                    } label: {
                        HStack {
                            if busy {
                                ProgressView()
                            }
                            Text("Créer et appliquer")
                        }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        do {
            categories = try await KDriveClient.shared.listCategories()
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }

    private func toggle(_ category: KCategory) {
        busy = true
        let assign = !hasTag(category)
        let ids = fileIds
        let categoryId = category.id
        Task { @MainActor in
            do {
                try await KDriveClient.shared.setCategory(fileIds: ids, categoryId: categoryId, assign: assign)
                onDone()
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
            busy = false
        }
    }

    private func createAndAssign() {
        busy = true
        let name = newName.trimmingCharacters(in: .whitespaces)
        let color = newColor
        let ids = fileIds
        Task { @MainActor in
            do {
                let category = try await KDriveClient.shared.createCategory(name: name, color: color)
                try await KDriveClient.shared.setCategory(fileIds: ids, categoryId: category.id, assign: true)
                onDone()
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
            busy = false
        }
    }
}
