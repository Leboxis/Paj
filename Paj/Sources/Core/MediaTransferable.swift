import Foundation
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Transferable pour Photos et Vidéos

struct MovieFileTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let tempDir = FileManager.default.temporaryDirectory
            let targetURL = tempDir.appendingPathComponent(UUID().uuidString + "_" + received.file.lastPathComponent)
            try? FileManager.default.removeItem(at: targetURL)
            try FileManager.default.copyItem(at: received.file, to: targetURL)
            return MovieFileTransferable(url: targetURL)
        }
    }
}

struct ImageFileTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { image in
            SentTransferredFile(image.url)
        } importing: { received in
            let tempDir = FileManager.default.temporaryDirectory
            let targetURL = tempDir.appendingPathComponent(UUID().uuidString + "_" + received.file.lastPathComponent)
            try? FileManager.default.removeItem(at: targetURL)
            try FileManager.default.copyItem(at: received.file, to: targetURL)
            return ImageFileTransferable(url: targetURL)
        }
    }
}

// MARK: - Chargeur de médias

enum MediaLoader {
    private static let timestampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        return df
    }()

    /// Charge un média de la photothèque vers un fichier temporaire en
    /// sandbox. Retourne (nom d'upload, URL du fichier) — le fichier reste
    /// sur disque (jamais chargé entièrement en mémoire) et doit être
    /// supprimé par l'appelant après l'upload.
    static func loadMedia(from item: PhotosPickerItem) async throws -> (name: String, url: URL)? {
        let isMovie = item.supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }

        // 1. Essai vidéo si le type est détecté comme vidéo/film
        //    (FileRepresentation copie déjà le média dans tmp/ en sandbox)
        if isMovie {
            if let movie = try? await item.loadTransferable(type: MovieFileTransferable.self) {
                let ext = movie.url.pathExtension.isEmpty ? "mp4" : movie.url.pathExtension
                return ("VID_\(timestampFormatter.string(from: Date())).\(ext)", movie.url)
            }
        }

        // 2. Essai représentation fichier image (PNG, HEIC, JPEG d'origine)
        if let imageFile = try? await item.loadTransferable(type: ImageFileTransferable.self) {
            let ext = imageFile.url.pathExtension.isEmpty ? "jpg" : imageFile.url.pathExtension
            return ("IMG_\(timestampFormatter.string(from: Date())).\(ext)", imageFile.url)
        }

        // 3. Essai données brutes directes (rare, petits fichiers) :
        //    écrites en fichier temporaire pour un upload streamé.
        if let data = try? await item.loadTransferable(type: Data.self) {
            let ext = isMovie ? "mp4" : "jpg"
            let prefix = isMovie ? "VID" : "IMG"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "." + ext)
            try data.write(to: url, options: .atomic)
            return ("\(prefix)_\(timestampFormatter.string(from: Date())).\(ext)", url)
        }

        // 4. Dernier essai vidéo si la détection initiale n'avait pas identifié le type
        if let movie = try? await item.loadTransferable(type: MovieFileTransferable.self) {
            let ext = movie.url.pathExtension.isEmpty ? "mp4" : movie.url.pathExtension
            return ("VID_\(timestampFormatter.string(from: Date())).\(ext)", movie.url)
        }

        return nil
    }
}

// MARK: - Téléchargement de fichiers pour partage natif

enum FileDownloadHelper {
    /// Télécharge un fichier kdrive et l'enregistre localement
    /// avec son vrai nom pour la feuille de partage iOS (Enregistrer dans Fichiers, AirDrop, etc.).
    /// Téléchargement streamé sur disque : aucun fichier entier en mémoire.
    static func downloadAndPrepareLocalURL(item: FileItem) async throws -> URL {
        let tempURL = try await KDriveClient.shared.downloadFileToTemporary(fileId: item.id)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent(item.name)
        try? FileManager.default.removeItem(at: fileURL)
        do {
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
        return fileURL
    }

    /// Supprime les fichiers téléchargés pour partage (réinitialisation).
    static func clearDownloads() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: - ShareSheet iOS

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
