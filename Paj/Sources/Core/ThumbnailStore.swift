import UIKit
import SwiftUI

/// Cache de miniatures à deux niveaux : NSCache (mémoire) + répertoire disque
/// plafonné (~250 Mo, éviction par plus ancien). La miniature est demandée au
/// serveur à la taille exacte de la cellule : le sous-échantillonnage est fait
/// côté kdrive, ce qui garde le défilement à 120 Hz.
final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private let memory = NSCache<NSString, UIImage>()
    private let diskDir: URL
    private let ioQueue = DispatchQueue(label: "com.paj.thumbs.io")
    private let maxDiskBytes = 250 * 1024 * 1024

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskDir = base.appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
        memory.countLimit = 800
    }

    func image(forKey key: String, fetch: @escaping () async throws -> Data) async -> UIImage? {
        if let hit = memory.object(forKey: key as NSString) { return hit }

        let url = diskDir.appendingPathComponent(Self.safeName(key))
        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            memory.setObject(img, forKey: key as NSString)
            return img
        }

        guard let data = try? await fetch(), !data.isEmpty, let img = UIImage(data: data) else { return nil }
        memory.setObject(img, forKey: key as NSString)

        let dir = diskDir
        let limit = maxDiskBytes
        ioQueue.async {
            try? data.write(to: url, options: .atomic)
            Self.trimDisk(dir: dir, maxBytes: limit)
        }
        return img
    }

    func clearAll() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: diskDir)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    func formattedSize() -> String {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: diskDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "0 o"
        }
        let total = files.reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    }

    private static func trimDisk(dir: URL, maxBytes: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return
        }
        var entries: [(url: URL, size: Int, date: Date)] = []
        var total = 0
        for f in files {
            let values = try? f.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let size = values?.fileSize ?? 0
            entries.append((f, size, values?.contentModificationDate ?? .distantPast))
            total += size
        }
        guard total > maxBytes else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? fm.removeItem(at: entry.url)
            total -= entry.size
            if total <= maxBytes { break }
        }
    }

    private static func safeName(_ key: String) -> String {
        String(key.map { c in
            (c.isLetter || c.isNumber || c == "_" || c == "-") ? c : "_"
        })
    }
}

/// Miniature kdrive chargée de façon asynchrone avec cache.
struct RemoteThumbnail: View {
    let file: FileItem
    var width: Int
    var height: Int
    var corner: CGFloat = 4

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(.systemGray5))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: file.isVideo ? "video" : "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .task(id: file.id) {
            let key = "t_\(file.id)_\(width)x\(height)"
            image = await ThumbnailStore.shared.image(forKey: key) {
                try await KDriveClient.shared.thumbnailData(fileId: file.id, width: width, height: height)
            }
        }
    }
}
