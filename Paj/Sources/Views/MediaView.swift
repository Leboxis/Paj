import SwiftUI

/// Onglet Médias : grille 3 colonnes façon Photos, toutes les images et vidéos
/// du drive (recherche profonde, triées par date de modification).
struct MediaView: View {
    @StateObject private var model = FileListModel { cursor in
        try await KDriveClient.shared.mediaLibrary(cursor: cursor)
    }

    @State private var viewerShown = false
    @State private var viewerIndex = 0

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            viewerIndex = index
                            viewerShown = true
                        } label: {
                            ZStack {
                                RemoteThumbnail(file: item, width: 400, height: 400, corner: 2)
                                    .aspectRatio(1, contentMode: .fit)
                                if item.isVideo {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onAppear { Task { await model.loadMoreIfNeeded(current: item) } }
                    }
                    if model.canLoadMore && !model.items.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .onAppear { Task { await model.loadMore() } }
                    }
                }
                .padding(2)
            }
            .navigationTitle("Médias")
            .refreshable { await model.refresh() }
            .task { await model.loadFirstPageIfNeeded() }
            .fullScreenCover(isPresented: $viewerShown) {
                MediaViewerView(items: model.items, index: $viewerIndex)
            }
            .overlay {
                if model.items.isEmpty && model.isLoading {
                    ProgressView()
                }
            }
            .overlay {
                if model.items.isEmpty && !model.isLoading && model.errorMessage == nil {
                    ContentUnavailableView("Aucun média", systemImage: "photo.on.rectangle.angled")
                }
            }
            .alert("Erreur", isPresented: Binding(get: { model.errorMessage != nil },
                                                  set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}
