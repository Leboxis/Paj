import Foundation

enum KDriveError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "App non configurée : token ou ID du drive manquant."
        case .http(let code, let message):
            return "Erreur API (\(code)) : \(message)"
        case .decoding:
            return "Réponse du serveur illisible."
        }
    }
}

/// Client HTTP pour l'API kdrive d'Infomaniak (https://api.infomaniak.com).
/// Le Bearer token est lu à chaque requête pour prendre en compte un changement
/// de configuration sans redémarrer l'app.
final class KDriveClient {
    static let shared = KDriveClient()

    private let session = URLSession.shared
    private let base = URL(string: "https://api.infomaniak.com")!

    private init() {}

    // MARK: - Plomberie

    private func request(path: String, query: [URLQueryItem] = []) throws -> URLRequest {
        guard AppConfig.isConfigured else { throw KDriveError.notConfigured }
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(AppConfig.token)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func perform(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw KDriveError.http(0, "Pas de réponse HTTP")
        }
        guard (200...299).contains(http.statusCode) else {
            throw KDriveError.http(http.statusCode, Self.errorDescription(data))
        }
        return data
    }

    private static func errorDescription(_ data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = obj["error"] as? [String: Any],
              let desc = error["description"] as? String else { return "erreur inconnue" }
        return desc
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await perform(try request(path: path, query: query))
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw KDriveError.decoding
        }
    }

    private static func paginationQuery(cursor: String?, extra: [URLQueryItem]) -> [URLQueryItem] {
        var q = extra
        if let cursor, !cursor.isEmpty {
            q.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return q
    }

    // MARK: - Lecture

    func listDirectory(id: Int, cursor: String?, orderBy: String, order: String, directoriesOnly: Bool = false) async throws -> Page<FileItem> {
        var extra = [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "with", value: "categories,is_favorite")
        ]
        if !orderBy.isEmpty && orderBy != "original" {
            extra.append(URLQueryItem(name: "order_by", value: orderBy))
            extra.append(URLQueryItem(name: "order", value: order))
        }
        if directoriesOnly {
            extra.append(URLQueryItem(name: "type", value: "dir"))
        }
        return try await get("3/drive/\(AppConfig.driveId)/files/\(id)/files", query: Self.paginationQuery(cursor: cursor, extra: extra))
    }

    func favorites(cursor: String?, orderBy: String, order: String, limit: Int = 100) async throws -> Page<FileItem> {
        var extra = [
            URLQueryItem(name: "limit", value: String(max(limit, 5))),
            URLQueryItem(name: "with", value: "categories,is_favorite")
        ]
        if !orderBy.isEmpty && orderBy != "original" {
            extra.append(URLQueryItem(name: "order_by", value: orderBy))
            extra.append(URLQueryItem(name: "order", value: order))
        }
        return try await get("3/drive/\(AppConfig.driveId)/files/favorites", query: Self.paginationQuery(cursor: cursor, extra: extra))
    }

    /// Derniers fichiers ajoutés/modifiés sur tout le drive (proxy des
    /// uploads récents), pagination par curseur.
    func lastModifiedFiles(cursor: String?, limit: Int = 12) async throws -> Page<FileItem> {
        try await get("3/drive/\(AppConfig.driveId)/files/last_modified", query: Self.paginationQuery(cursor: cursor, extra: [
            URLQueryItem(name: "limit", value: String(max(limit, 5))),
            URLQueryItem(name: "with", value: "categories,is_favorite")
        ]))
    }

    /// Fichiers portant un tag donné (recherche par id de catégorie).
    func filesInCategory(_ categoryId: Int, cursor: String?) async throws -> Page<FileItem> {
        try await get("3/drive/\(AppConfig.driveId)/files/search", query: Self.paginationQuery(cursor: cursor, extra: [
            URLQueryItem(name: "category", value: String(categoryId)),
            URLQueryItem(name: "with", value: "categories,is_favorite"),
            URLQueryItem(name: "order_by", value: "last_modified_at"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "limit", value: "100")
        ]))
    }

    /// Recherche globale de fichiers par mot-clé sur l'ensemble du drive.
    func searchFiles(query: String, cursor: String?) async throws -> Page<FileItem> {
        try await get("3/drive/\(AppConfig.driveId)/files/search", query: Self.paginationQuery(cursor: cursor, extra: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "with", value: "categories,is_favorite"),
            URLQueryItem(name: "limit", value: "100")
        ]))
    }

    func driveInfo() async throws -> DriveInfo {
        struct Resp: Decodable { let data: DriveInfo? }
        let resp: Resp = try await get("2/drive/\(AppConfig.driveId)")
        guard let info = resp.data else { throw KDriveError.decoding }
        return info
    }

    /// Nombre de fichiers et sous-dossiers dans un dossier.
    func directoryCount(fileId: Int) async throws -> DirectoryCountInfo {
        struct Resp: Decodable { let data: DirectoryCountInfo? }
        let resp: Resp = try await get("3/drive/\(AppConfig.driveId)/files/\(fileId)/count")
        guard let info = resp.data else { throw KDriveError.decoding }
        return info
    }

    /// Taille totale d'un dossier avec tous ses enfants (profondeur illimitée).
    func directorySize(fileId: Int) async throws -> DirectorySizeInfo {
        struct Resp: Decodable { let data: DirectorySizeInfo? }
        let resp: Resp = try await get("2/drive/\(AppConfig.driveId)/files/\(fileId)/sizes", query: [
            URLQueryItem(name: "depth", value: "unlimited")
        ])
        guard let info = resp.data else { throw KDriveError.decoding }
        return info
    }


    // MARK: - Actions

    func setFavorite(_ item: FileItem, favorite: Bool) async throws {
        var req = try request(path: "2/drive/\(AppConfig.driveId)/files/\(item.id)/favorite")
        req.httpMethod = favorite ? "POST" : "DELETE"
        _ = try await perform(req)
    }

    func rename(_ item: FileItem, to name: String) async throws {
        var req = try request(path: "2/drive/\(AppConfig.driveId)/files/\(item.id)/rename")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["name": name])
        _ = try await perform(req)
    }

    func delete(_ item: FileItem) async throws {
        var req = try request(path: "2/drive/\(AppConfig.driveId)/files/\(item.id)")
        req.httpMethod = "DELETE"
        _ = try await perform(req)
    }

    func move(_ item: FileItem, to directoryId: Int) async throws {
        _ = try await performJSON("3/drive/\(AppConfig.driveId)/files/\(item.id)/move/\(directoryId)",
                                  method: "POST",
                                  body: ["conflict": "rename"])
    }

    /// Création d'un nouveau dossier dans un dossier parent.
    @discardableResult
    func createDirectory(name: String, in directoryId: Int, color: String? = nil) async throws -> FileItem {
        struct Resp: Decodable { let data: FileItem? }
        var body: [String: Any] = ["name": name]
        if let color { body["color"] = color }
        let data = try await performJSON("3/drive/\(AppConfig.driveId)/files/\(directoryId)/directory",
                                         method: "POST",
                                         body: body)
        guard let item = (try? JSONDecoder().decode(Resp.self, from: data))?.data else {
            throw KDriveError.decoding
        }
        return item
    }

    /// Téléversement d'un nouveau fichier (photo, vidéo, document) dans un dossier.
    /// Streamé depuis le disque via URLSession (aucun chargement complet en
    /// mémoire : les vidéos volumineuses ne font pas planter l'app).
    @discardableResult
    func uploadFile(name: String, fileURL: URL, directoryId: Int) async throws -> FileItem {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? 0
        var req = try request(path: "3/drive/\(AppConfig.driveId)/upload", query: [
            URLQueryItem(name: "directory_id", value: String(directoryId)),
            URLQueryItem(name: "file_name", value: name),
            URLQueryItem(name: "total_size", value: String(fileSize)),
            URLQueryItem(name: "conflict", value: "rename"),
            URLQueryItem(name: "with", value: "categories,is_favorite")
        ])
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: req, fromFile: fileURL)
        try Self.check(response: response, data: data)
        return Self.decodeUploadResponse(data, fallbackName: name, size: fileSize)
    }

    /// Interprète la réponse du téléversement : `{"data": {FileV3}}`, ou une
    /// forme simplifiée `{id, name, type}`, ou rien d'exploitable (fichier synthétique).
    private static func decodeUploadResponse(_ data: Data, fallbackName: String, size: Int) -> FileItem {
        struct Resp: Decodable { let data: FileItem? }
        struct SimpleResp: Decodable {
            struct SimpleData: Decodable {
                let id: Int?
                let name: String?
                let type: String?
            }
            let data: SimpleData?
        }
        if let item = (try? JSONDecoder().decode(Resp.self, from: data))?.data {
            return item
        }
        if let simple = (try? JSONDecoder().decode(SimpleResp.self, from: data))?.data, let id = simple.id {
            return FileItem(id: id, name: simple.name ?? fallbackName, type: simple.type ?? "file", size: size, mimeType: nil, extensionType: nil, createdAt: nil, lastModifiedAt: nil, addedAt: nil, isFavorite: nil, categories: nil, color: nil, deletedAt: nil)
        }
        return FileItem(id: 0, name: fallbackName, type: "file", size: size, mimeType: nil, extensionType: nil, createdAt: nil, lastModifiedAt: nil, addedAt: nil, isFavorite: nil, categories: nil, color: nil, deletedAt: nil)
    }

    private static func check(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw KDriveError.http(0, "Pas de réponse HTTP")
        }
        guard (200...299).contains(http.statusCode) else {
            throw KDriveError.http(http.statusCode, Self.errorDescription(data))
        }
    }


    // MARK: - Tags (catégories)

    func listCategories() async throws -> [KCategory] {
        struct Resp: Decodable { let data: [KCategory]? }
        let resp: Resp = try await get("2/drive/\(AppConfig.driveId)/categories")
        return resp.data ?? []
    }

    func createCategory(name: String, color: String) async throws -> KCategory {
        struct Resp: Decodable { let data: KCategory? }
        let data = try await performJSON("2/drive/\(AppConfig.driveId)/categories",
                                         method: "POST",
                                         body: ["name": name, "color": color])
        guard let category = (try? JSONDecoder().decode(Resp.self, from: data))?.data else {
            throw KDriveError.decoding
        }
        return category
    }

    /// Applique (ou retire) un tag sur plusieurs fichiers en un seul appel.
    func setCategory(fileIds: [Int], categoryId: Int, assign: Bool) async throws {
        _ = try await performJSON("2/drive/\(AppConfig.driveId)/files/categories/\(categoryId)",
                                  method: assign ? "POST" : "DELETE",
                                  body: ["file_ids": fileIds])
    }

    private func performJSON(_ path: String, method: String, body: [String: Any]) async throws -> Data {
        var req = try request(path: path)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(req)
    }

    // MARK: - Fichiers texte

    /// Contenu brut d'un fichier (téléchargement direct).
    func downloadData(fileId: Int) async throws -> Data {
        let req = try request(path: "2/drive/\(AppConfig.driveId)/files/\(fileId)/download")
        return try await perform(req)
    }

    /// Télécharge un fichier vers une URL temporaire gérée par URLSession
    /// (streaming disque : aucune limite de taille en mémoire). L'appelant
    /// déplace ou supprime ce fichier temporaire ensuite.
    func downloadFileToTemporary(fileId: Int) async throws -> URL {
        let req = try request(path: "2/drive/\(AppConfig.driveId)/files/\(fileId)/download")
        let (url, response) = try await session.download(for: req)
        guard let http = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: url)
            throw KDriveError.http(0, "Pas de réponse HTTP")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = (try? Data(contentsOf: url)) ?? Data()
            try? FileManager.default.removeItem(at: url)
            throw KDriveError.http(http.statusCode, Self.errorDescription(body))
        }
        return url
    }

    /// Enregistre le nouveau contenu d'un fichier existant :
    /// upload avec file_id = nouvelle version côté kdrive
    /// (validé en direct : ni conflict ni directory_id dans ce mode).
    func saveFileContent(_ item: FileItem, data: Data) async throws {
        var req = try request(path: "3/drive/\(AppConfig.driveId)/upload", query: [
            URLQueryItem(name: "file_id", value: String(item.id)),
            URLQueryItem(name: "total_size", value: String(data.count))
        ])
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        _ = try await perform(req)
    }

    // MARK: - Corbeille

    func trash(cursor: String?) async throws -> Page<FileItem> {
        try await get("3/drive/\(AppConfig.driveId)/trash", query: Self.paginationQuery(cursor: cursor, extra: [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "with", value: "categories,is_favorite")
        ]))
    }

    func restore(_ item: FileItem) async throws {
        var req = try request(path: "2/drive/\(AppConfig.driveId)/trash/\(item.id)/restore")
        req.httpMethod = "POST"
        _ = try await perform(req)
    }

    func deletePermanently(_ item: FileItem) async throws {
        var req = try request(path: "2/drive/\(AppConfig.driveId)/trash/\(item.id)")
        req.httpMethod = "DELETE"
        _ = try await perform(req)
    }

    func emptyTrash() async throws {
        var req = try request(path: "2/drive/\(AppConfig.driveId)/trash")
        req.httpMethod = "DELETE"
        _ = try await perform(req)
    }

    // MARK: - Médias

    /// URL temporaire signée (1 h) : streaming direct dans AVPlayer,
    /// lecture distante dans Safari, etc.
    func temporaryUrl(for item: FileItem) async throws -> URL {
        struct Resp: Decodable { let data: TemporaryUrlData? }
        let resp: Resp = try await get("2/drive/\(AppConfig.driveId)/files/\(item.id)/temporary_url", query: [
            URLQueryItem(name: "duration", value: "3600")
        ])
        guard let s = resp.data?.temporaryUrl, let url = URL(string: s) else { throw KDriveError.decoding }
        return url
    }

    func thumbnailData(fileId: Int, width: Int, height: Int) async throws -> Data {
        // L'API kdrive limite les miniatures à 10...400 px (422 au-delà).
        let w = min(max(width, 10), 400)
        let h = min(max(height, 10), 400)
        let req = try request(path: "2/drive/\(AppConfig.driveId)/files/\(fileId)/thumbnail", query: [
            URLQueryItem(name: "width", value: String(w)),
            URLQueryItem(name: "height", value: String(h))
        ])
        return try await perform(req)
    }

    /// Aperçu haute résolution pour la visionneuse plein écran.
    func previewData(fileId: Int, width: Int) async throws -> Data {
        let req = try request(path: "2/drive/\(AppConfig.driveId)/files/\(fileId)/preview", query: [
            URLQueryItem(name: "width", value: String(width)),
            URLQueryItem(name: "quality", value: "90")
        ])
        return try await perform(req)
    }
}
