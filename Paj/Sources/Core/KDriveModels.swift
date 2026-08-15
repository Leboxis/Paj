import Foundation

/// Élément du drive (fichier ou dossier) — champs du schéma FileV3/DirectoryV3
/// réellement utilisés par l'app.
struct FileItem: Identifiable, Hashable, Codable {
    var id: Int
    var name: String
    let type: String
    let size: Int?
    let mimeType: String?
    let extensionType: String?
    let createdAt: Int?
    let lastModifiedAt: Int?
    let addedAt: Int?
    var isFavorite: Bool?

    var isDirectory: Bool { type == "directory" }

    var isImage: Bool { mimeType?.hasPrefix("image/") ?? false }
    var isVideo: Bool { mimeType?.hasPrefix("video/") ?? false }
    var isMedia: Bool { isImage || isVideo }

    var fileDate: Date? {
        if let t = lastModifiedAt { return Date(timeIntervalSince1970: TimeInterval(t)) }
        if let t = addedAt { return Date(timeIntervalSince1970: TimeInterval(t)) }
        if let t = createdAt { return Date(timeIntervalSince1970: TimeInterval(t)) }
        return nil
    }

    /// Racine du drive (id 1 validé contre l'API en direct).
    static func root() -> FileItem {
        FileItem(id: AppConfig.rootDirectoryId,
                 name: "Mon drive",
                 type: "directory",
                 size: nil,
                 mimeType: nil,
                 extensionType: nil,
                 createdAt: nil,
                 lastModifiedAt: nil,
                 addedAt: nil,
                 isFavorite: nil)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, size
        case mimeType = "mime_type"
        case extensionType = "extension_type"
        case createdAt = "created_at"
        case lastModifiedAt = "last_modified_at"
        case addedAt = "added_at"
        case isFavorite = "is_favorite"
    }
}

/// Enveloppe commune aux réponses paginées v3 et simples v2 :
/// `{"result": "...", "data": [...], "cursor": "...", "has_more": bool}`.
struct Page<T: Decodable>: Decodable {
    let result: String?
    let data: [T]?
    let cursor: String?
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case result, data, cursor
        case hasMore = "has_more"
    }
}

struct TemporaryUrlData: Decodable {
    let temporaryUrl: String

    enum CodingKeys: String, CodingKey {
        case temporaryUrl = "temporary_url"
    }
}

struct DriveInfo: Decodable {
    let id: Int
    let name: String
    let size: Int
    let usedSize: Int

    enum CodingKeys: String, CodingKey {
        case id, name, size
        case usedSize = "used_size"
    }
}

/// Champs de tri supportés par l'API (order_by), triés côté serveur.
enum SortField: String, CaseIterable, Identifiable {
    case name
    case lastModified = "last_modified_at"
    case size
    case type

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return "Nom"
        case .lastModified: return "Date de modification"
        case .size: return "Taille"
        case .type: return "Type"
        }
    }
}
