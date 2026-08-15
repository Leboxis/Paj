import SwiftUI

/// Onglet Corbeille : éléments supprimés du drive, restauration ou
/// suppression définitive, vue grille ou liste.
struct TrashView: View {
    @StateObject private var model = FileListModel { cursor in
        try await KDriveClient.shared.trash(cursor: cursor)
    }

    @AppStorage("trash.isGrid") private var gridView = true
    @State private var confirmEmpty = false
    @State private var permanentItem: FileItem?

    var body: some View {
        NavigationStack {
            Group {
                if gridView {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 10)], spacing: 12) {
                            ForEach(model.items) { item in
                                cell(item)
                            }
                        }
                        .padding(12)
                        if model.canLoadMore && !model.items.isEmpty {
                            Color.clear
                                .frame(height: 4)
                                .onAppear { Task { await model.loadMore() } }
                        }
                    }
                } else {
                    List {
                        ForEach(model.items) { item in
                            row(item)
                        }
                        if model.canLoadMore && !model.items.isEmpty {
                            Color.clear
                                .frame(height: 4)
                                .onAppear { Task { await model.loadMore() } }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Corbeille")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { gridView.toggle() }
                    } label: {
                        Image(systemName: gridView ? "list.bullet" : "square.grid.2x2")
                    }
                    .accessibilityLabel(gridView ? "Vue liste" : "Vue grille")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        confirmEmpty = true
                    } label: {
                        Label("Vider", systemImage: "trash")
                    }
                    .disabled(model.items.isEmpty)
                }
            }
            .refreshable { await model.refresh() }
            .task { await model.loadFirstPageIfNeeded() }
            .alert("Vider la corbeille ?", isPresented: $confirmEmpty) {
                Button("Vider", role: .destructive) {
                    Task {
                        do {
                            try await KDriveClient.shared.emptyTrash()
                            await model.refresh()
                        } catch {
                            model.errorMessage = error.localizedDescription
                        }
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Tous les éléments seront supprimés définitivement.")
            }
            .alert("Supprimer définitivement « \(permanentItem?.name ?? "") » ?",
                   isPresented: Binding(get: { permanentItem != nil },
                                        set: { if !$0 { permanentItem = nil } })) {
                Button("Supprimer", role: .destructive) {
                    if let item = permanentItem {
                        Task {
                            do {
                                try await KDriveClient.shared.deletePermanently(item)
                                model.items.removeAll { $0.id == item.id }
                            } catch {
                                model.errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("L'élément sera supprimé définitivement du drive.")
            }
            .alert("Erreur", isPresented: Binding(get: { model.errorMessage != nil },
                                                  set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .overlay {
                if model.items.isEmpty && model.isLoading {
                    ProgressView()
                }
            }
            .overlay {
                if model.items.isEmpty && !model.isLoading && model.errorMessage == nil {
                    ContentUnavailableView("Corbeille vide", systemImage: "trash")
                }
            }
        }
    }

    private func subtitle(for item: FileItem) -> String {
        if let date = item.deletionDate {
            return "Supprimé le " + date.formatted(date: .abbreviated, time: .shortened)
        }
        return item.subtitle
    }

    private func row(_ item: FileItem) -> some View {
        FileRow(item: item, subtitleText: subtitle(for: item))
            .contextMenu { contextActions(item) }
            .onAppear { Task { await model.loadMoreIfNeeded(current: item) } }
    }

    private func cell(_ item: FileItem) -> some View {
        FileGridCell(item: item)
            .contextMenu { contextActions(item) }
            .onAppear { Task { await model.loadMoreIfNeeded(current: item) } }
    }

    @ViewBuilder
    private func contextActions(_ item: FileItem) -> some View {
        Button {
            Task {
                do {
                    try await KDriveClient.shared.restore(item)
                    model.items.removeAll { $0.id == item.id }
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        } label: {
            Label("Restaurer", systemImage: "arrow.uturn.backward")
        }
        Button(role: .destructive) {
            permanentItem = item
        } label: {
            Label("Supprimer définitivement", systemImage: "trash")
        }
    }
}
