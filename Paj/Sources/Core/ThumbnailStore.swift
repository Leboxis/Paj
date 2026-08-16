import UIKit
import SwiftUI

/// Cache de miniatures à deux niveaux : NSCache (mémoire, plafonnée par
/// coût en pixels décodés) + répertoire disque plafonné (~250 Mo, éviction
/// par plus ancien). La miniature est demandée au serveur à la taille exacte
/// de la cellule : le sous-échantillonnage est fait côté kdrive, ce qui
/// garde le défilement fluide à 120 Hz.
final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private let memory = NSCache<NSString, UIImage>()
    private let diskDir: URL
    private let ioQueue = DispatchQueue(label: "com.paj.thumbs.io", qos: .utility)
    private let syncQueue = DispatchQueue(label: "com.paj.thumbs.sync")
    private let maxDiskBytes = 250 * 1024 * 1024
    private let maxMemoryBytes = 120 * 1024 * 1024

    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var lastTrimDate = Date.distantPast

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskDir = base.appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
        memory.totalCostLimit = maxMemoryBytes
        memory.countLimit = 1500

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.memory.removeAllObjects()
        }
    }

    func image(forKey key: String, fetch: @escaping () async throws -> Data) async -> UIImage? {
        if let hit = memory.object(forKey: key as NSString) { return hit }

        var existing: Task<UIImage?, Never>?
        var started: Task<UIImage?, Never>?

        syncQueue.sync {
            if let task = inFlight[key] {
                existing = task
            } else {
                let newTask = Task { [weak self] () -> UIImage? in
                    guard let self else { return nil }
                    return await self.loadFromDiskOrFetch(key: key, fetch: fetch)
                }
                inFlight[key] = newTask
                started = newTask
            }
        }

        if let existing {
            return await existing.value
        }
        guard let started else { return nil }
        let result = await started.value

        syncQueue.sync {
            inFlight[key] = nil
        }
        return result
    }

    private func loadFromDiskOrFetch(key: String, fetch: @escaping () async throws -> Data) async -> UIImage? {
        let url = diskDir.appendingPathComponent(Self.safeName(key))
        let cached = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }.value

        if let cached {
            memory.setObject(cached, forKey: key as NSString, cost: Self.pixelCost(of: cached))
            return cached
        }

        guard let data = try? await fetch(), !data.isEmpty else { return nil }
        guard let image = await Task.detached(priority: .utility, operation: { UIImage(data: data) }).value else {
            return nil
        }
        memory.setObject(image, forKey: key as NSString, cost: Self.pixelCost(of: image))

        let dir = diskDir
        let limit = maxDiskBytes
        ioQueue.async { [weak self] in
            try? data.write(to: url, options: .atomic)
            guard let self else { return }
            let now = Date()
            if now.timeIntervalSince(self.lastTrimDate) > 60 {
                self.lastTrimDate = now
                Self.trimDisk(dir: dir, maxBytes: limit)
            }
        }
        return image
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

    /// Coût mémoire réel de l'image décodée (octets de pixels).
    private static func pixelCost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        return cg.bytesPerRow * cg.height
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

struct RemoteThumbnail: View {
    let file: FileItem
    var width: Int
    var height: Int
    var corner: CGFloat = 8

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: file.isVideo ? "video.fill" : "photo.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(file.isVideo ? (Color(hex: "#60A5FA") ?? .blue) : (Color(hex: "#34D399") ?? .green))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .task(id: file.id) {
            let key = "t_\(file.id)_\(width)x\(height)"
            image = await ThumbnailStore.shared.image(forKey: key) {
                try await KDriveClient.shared.thumbnailData(fileId: file.id, width: width, height: height)
            }
            if let img = image, file.isVideo {
                await VideoMetadataStore.shared.register(fileId: file.id, imageWidth: img.size.width, imageHeight: img.size.height)
            }
        }
    }
}
