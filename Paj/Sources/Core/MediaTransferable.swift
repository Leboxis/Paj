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

    static func loadMedia(from item: PhotosPickerItem) async throws -> (name: String, data: Data)? {
        let isMovie = item.supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }

        // 1. Essai vidéo si le type est détecté comme vidéo/film
        if isMovie {
            if let movie = try? await item.loadTransferable(type: MovieFileTransferable.self) {
                let data = try Data(contentsOf: movie.url)
                let ext = movie.url.pathExtension.isEmpty ? "mp4" : movie.url.pathExtension
                let name = "VID_\(timestampFormatter.string(from: Date())).\(ext)"
                try? FileManager.default.removeItem(at: movie.url)
                return (name, data)
            }
        }

        // 2. Essai représentation fichier image (PNG, HEIC, JPEG d'origine)
        if let imageFile = try? await item.loadTransferable(type: ImageFileTransferable.self) {
            let data = try Data(contentsOf: imageFile.url)
            let ext = imageFile.url.pathExtension.isEmpty ? "jpg" : imageFile.url.pathExtension
            let name = "IMG_\(timestampFormatter.string(from: Date())).\(ext)"
            try? FileManager.default.removeItem(at: imageFile.url)
            return (name, data)
        }

        // 3. Essai données brutes directes
        if let data = try? await item.loadTransferable(type: Data.self) {
            let ext = isMovie ? "mp4" : "jpg"
            let prefix = isMovie ? "VID" : "IMG"
            let name = "\(prefix)_\(timestampFormatter.string(from: Date())).\(ext)"
            return (name, data)
        }

        // 4. Dernier essai vidéo si la détection initiale n'avait pas identifié le type
        if let movie = try? await item.loadTransferable(type: MovieFileTransferable.self) {
            let data = try Data(contentsOf: movie.url)
            let ext = movie.url.pathExtension.isEmpty ? "mp4" : movie.url.pathExtension
            let name = "VID_\(timestampFormatter.string(from: Date())).\(ext)"
            try? FileManager.default.removeItem(at: movie.url)
            return (name, data)
        }

        return nil
    }
}

// MARK: - Téléchargement de fichiers pour partage natif

enum FileDownloadHelper {
    /// Télécharge les données d'un fichier kdrive et l'enregistre localement
    /// avec son vrai nom pour la feuille de partage iOS (Enregistrer dans Fichiers, AirDrop, etc.).
    static func downloadAndPrepareLocalURL(item: FileItem) async throws -> URL {
        let data = try await KDriveClient.shared.downloadData(fileId: item.id)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent(item.name)
        try? FileManager.default.removeItem(at: fileURL)
        try data.write(to: fileURL)
        return fileURL
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
