import Foundation
import SwiftUI

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
    var categories: [FileCategoryLink]?
    var color: String?
    var deletedAt: Int?

    var isDirectory: Bool { type == "dir" || type == "directory" }

    var deletionDate: Date? {
        deletedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    /// IDs des tags appliqués au fichier (l'API liste les ids ; les noms et
    /// couleurs viennent de CategoryStore).
    var tagIDs: [Int] {
        (categories ?? []).map(\.categoryId)
    }

    var categoryIDs: Set<Int> {
        Set(tagIDs)
    }

    var isImage: Bool { mimeType?.hasPrefix("image/") ?? false }
    var isVideo: Bool { mimeType?.hasPrefix("video/") ?? false }
    var isMedia: Bool { isImage || isVideo }

    /// Fichiers texte éditables (.txt, .md, .log ou mime text/*).
    var isTextFile: Bool {
        if let m = mimeType, m.hasPrefix("text/") { return true }
        let ext = (name as NSString).pathExtension.lowercased()
        return ["txt", "md", "log"].contains(ext)
    }

    var fileDate: Date? {
        if let t = lastModifiedAt { return Date(timeIntervalSince1970: TimeInterval(t)) }
        if let t = addedAt { return Date(timeIntervalSince1970: TimeInterval(t)) }
        if let t = createdAt { return Date(timeIntervalSince1970: TimeInterval(t)) }
        return nil
    }

    /// Racine du drive (dossier « Private », id 5 — validé contre l'API).
    static func root() -> FileItem {
        FileItem(id: AppConfig.rootDirectoryId,
                 name: "Accueil",
                 type: "dir",
                 size: nil,
                 mimeType: nil,
                 extensionType: nil,
                 createdAt: nil,
                 lastModifiedAt: nil,
                 addedAt: nil,
                 isFavorite: nil,
                 categories: nil,
                 color: nil,
                 deletedAt: nil)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, size
        case mimeType = "mime_type"
        case extensionType = "extension_type"
        case createdAt = "created_at"
        case lastModifiedAt = "last_modified_at"
        case addedAt = "added_at"
        case isFavorite = "is_favorite"
        case categories
        case color
        case deletedAt = "deleted_at"
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

struct DirectoryCountInfo: Decodable {
    let count: Int
    let files: Int
    let directories: Int
}

struct DirectorySizeInfo: Decodable {
    let size: Int
    let storageSize: Int?

    enum CodingKeys: String, CodingKey {
        case size
        case storageSize = "storage_size"
    }
}


/// Champs de tri supportés par l'API (order_by), triés côté serveur.
/// `original` demande l'ordre natif kdrive (paramètres de tri omis :
/// ordre personnalisé du drive).
enum SortField: String, CaseIterable, Identifiable {
    case original
    case name
    case lastModified = "last_modified_at"
    case size
    case duration
    case type

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Original"
        case .name: return "Nom"
        case .lastModified: return "Date de modification"
        case .size: return "Taille"
        case .duration: return "Durée vidéo"
        case .type: return "Type"
        }
    }

    /// À envoyer comme order_by à l'API (vide = ordre natif).
    var apiValue: String {
        switch self {
        case .original, .duration: return ""
        default: return rawValue
        }
    }
}


// MARK: - Tags (catégories kdrive)

/// Tag kdrive (« catégorie » du drive).
struct KCategory: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let color: String?

    var swatch: Color { Color(hex: color) ?? Color(.systemGray) }
}

/// Lien fichier ↔ catégorie tel que renvoyé dans FileV3.categories.
struct FileCategoryLink: Codable, Hashable {
    let categoryId: Int
    let category: KCategory?

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case category
    }
}

extension Color {
    /// Couleur depuis une chaîne hexadécimale « #RRGGBB » (format kdrive).
    init?(hex: String?) {
        guard let hex else { return nil }
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255.0,
                  green: Double((v >> 8) & 0xFF) / 255.0,
                  blue: Double(v & 0xFF) / 255.0)
    }
}
