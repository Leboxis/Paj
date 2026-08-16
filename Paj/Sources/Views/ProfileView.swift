import SwiftUI

/// Onglet Profil : stockage du drive (pourcentage, restant, total),
/// uploads récents et favoris les plus consultés (3 miniatures + page
/// détaillée avec défilement infini), accès à la corbeille.
struct ProfileView: View {
    @State private var driveInfo: DriveInfo?
    @State private var uploads: [FileItem] = []
    @State private var favorites: [FileItem] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                storageSection
                uploadsSection
                favoritesSection
                trashSection
            }
            .navigationTitle("Profil")
            .refreshable { await loadAll() }
            .task { await loadAll() }
            .onReceive(NotificationCenter.default.publisher(for: .pajTabSelected)) { note in
                if Notification.Name.isTabSelected(note, .profile) {
                    Task { await loadAll() }
                }
            }
            .overlay {
                if loading {
                    ProgressView()
                }
            }
        }
    }

    // MARK: - Stockage

    @ViewBuilder
    private var storageSection: some View {
        Section("Stockage du drive") {
            if let info = driveInfo {
                let used = Double(info.usedSize)
                let total = Double(info.size)
                let free = max(total - used, 0)
                let fraction = total > 0 ? used / total : 0
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(info.name)
                            .font(.headline)
                        Spacer()
                        Text("\(Int((fraction * 100).rounded())) % utilisés")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(fraction > 0.9 ? .red : .secondary)
                    }
                    ProgressView(value: fraction)
                        .tint(fraction > 0.9 ? .red : .accentColor)
                    Text("\(Self.byteString(free)) disponibles sur \(Self.byteString(total))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Text("Impossible de charger le stockage.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Uploads récents

    private var uploadsSection: some View {
        Section("Uploads récents") {
            NavigationLink {
                PagedFilesView(title: "Uploads récents") { cursor in
                    try await KDriveClient.shared.lastModifiedFiles(cursor: cursor, limit: 12)
                }
            } label: {
                sectionRow(items: uploads)
            }
        }
    }

    // MARK: - Favoris les plus consultés

    private var favoritesSection: some View {
        Section("Favoris les plus consultés") {
            NavigationLink {
                PagedFilesView(title: "Favoris les plus consultés") { cursor in
                    try await KDriveClient.shared.favorites(cursor: cursor,
                                                            orderBy: "last_modified_at",
                                                            order: "desc",
                                                            limit: 12)
                }
            } label: {
                sectionRow(items: favorites)
            }
        }
    }

    // MARK: - Corbeille

    private var trashSection: some View {
        Section {
            NavigationLink {
                TrashScreen()
            } label: {
                Label("Accéder à la corbeille", systemImage: "trash.fill")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Commun

    private func sectionRow(items: [FileItem]) -> some View {
        HStack(spacing: 8) {
            ForEach(items.prefix(3)) { item in
                ProfileThumb(item: item)
            }
            if items.isEmpty {
                Text("Aucun élément")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private static func byteString(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func loadAll() async {
        loading = driveInfo == nil && uploads.isEmpty && favorites.isEmpty
        async let info = KDriveClient.shared.driveInfo()
        async let up = KDriveClient.shared.lastModifiedFiles(cursor: nil, limit: 12)
        async let fav = KDriveClient.shared.favorites(cursor: nil, orderBy: "last_modified_at", order: "desc", limit: 12)
        driveInfo = try? await info
        uploads = (try? await up)?.data ?? []
        favorites = (try? await fav)?.data ?? []
        loading = false
    }
}

/// Miniature carrée compacte pour les zones du profil.
struct ProfileThumb: View {
    let item: FileItem

    var body: some View {
        ZStack {
            if item.isMedia {
                RemoteThumbnail(file: item, width: 200, height: 200, corner: 8)
            } else {
                FileIcon(item: item, size: 28)
            }
            if item.isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        }
        .frame(width: 64, height: 64)
    }
}

/// Page détaillée : grille paginée avec défilement infini automatique.
struct PagedFilesView: View {
    let title: String
    var loader: (String?) async throws -> Page<FileItem>

    @AppStorage("cardGridColumns") private var cardGridColumns: Int = 3

    @State private var items: [FileItem] = []
    @State private var cursor: String?
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var viewerShown = false
    @State private var viewerIndex = 0
    @State private var infoItem: FileItem?
    @State private var textItem: FileItem?

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: max(1, cardGridColumns))
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(items) { item in
                    cell(item)
                        .onAppear {
                            loadMoreIfNeeded(current: item)
                        }
                }
            }
            .padding(12)

            if isLoading && !items.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await refresh()
        }
        .task {
            if items.isEmpty { await loadMore() }
        }
        .fullScreenCover(isPresented: $viewerShown) {
            MediaViewerView(items: items.filter { $0.isMedia }, index: $viewerIndex)
        }
        .sheet(item: $infoItem) { FileInfoSheet(item: $0) }
        .sheet(item: $textItem) { TextFileView(item: $0) }
        .alert("Erreur", isPresented: Binding(get: { errorMessage != nil },
                                              set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .overlay {
            if items.isEmpty && isLoading {
                ProgressView()
            }
        }
        .overlay {
            if items.isEmpty && !isLoading && errorMessage == nil {
                ContentUnavailableView("Aucun élément", systemImage: "tray")
            }
        }
    }

    private func refresh() async {
        cursor = nil
        hasMore = true
        items.removeAll()
        await loadMore()
    }

    private func loadMoreIfNeeded(current: FileItem) {
        guard hasMore && !isLoading, !items.isEmpty else { return }
        guard let idx = items.firstIndex(where: { $0.id == current.id }),
              items.count - idx <= 6 else { return }
        Task { await loadMore() }
    }

    private func loadMore() async {
        guard !isLoading && hasMore else { return }
        isLoading = true
        do {
            let page = try await loader(cursor)
            let existingIDs = Set(items.map(\.id))
            let incoming = (page.data ?? []).filter { !existingIDs.contains($0.id) }
            items.append(contentsOf: incoming)
            cursor = page.cursor
            hasMore = page.hasMore ?? !((page.cursor ?? "").isEmpty)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func cell(_ item: FileItem) -> some View {
        Button {
            if item.isMedia {
                let media = items.filter { $0.isMedia }
                viewerIndex = media.firstIndex(where: { $0.id == item.id }) ?? 0
                viewerShown = true
            } else if item.isTextFile {
                textItem = item
            } else {
                infoItem = item
            }
        } label: {
            FileGridCell(item: item)
        }
        .buttonStyle(.plain)
    }
}
