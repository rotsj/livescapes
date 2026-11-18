import AppKit
import SwiftUI

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let memory = NSCache<NSURL, NSImage>()

    private init() {
        memory.countLimit = 300
    }

    func image(for url: URL) -> NSImage? {
        if let cached = memory.object(forKey: url as NSURL) {
            return cached
        }
        let diskURL = diskCacheURL(for: url)
        if FileManager.default.fileExists(atPath: diskURL.path),
           let diskImage = NSImage(contentsOf: diskURL) {
            memory.setObject(diskImage, forKey: url as NSURL)
            return diskImage
        }
        return nil
    }

    func store(_ image: NSImage, data: Data, for url: URL) {
        memory.setObject(image, forKey: url as NSURL)
        let diskURL = diskCacheURL(for: url)
        try? FileManager.default.createDirectory(at: diskURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: diskURL, options: .atomic)
    }

    private func diskCacheURL(for url: URL) -> URL {
        let dir = AppPaths.cacheDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
        let components = url.pathComponents
        if url.lastPathComponent == "thumbnail", components.count >= 2 {
            let parentID = components[components.count - 2]
            return dir.appendingPathComponent("\(parentID).png")
        }
        let filename = url.lastPathComponent.isEmpty ? "\(abs(url.absoluteString.hashValue)).png" : url.lastPathComponent
        return dir.appendingPathComponent(filename)
    }
}

struct CachedThumbnailView: View {
    let url: URL?
    var fallbackURL: URL? = nil
    let localPath: String?

    @State private var loadedImage: NSImage?
    @State private var isLoading: Bool = false
    @State private var failed: Bool = false

    var body: some View {
        Group {
            if let localPath, let img = NSImage(contentsOfFile: localPath) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let loadedImage {
                Image(nsImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: failed ? "exclamationmark.triangle" : "film")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .task(id: url) {
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        if let localPath, FileManager.default.fileExists(atPath: localPath) {
            return
        }
        guard let url else { return }
        if let cached = ThumbnailCache.shared.image(for: url) {
            loadedImage = cached
            return
        }
        if let fallbackURL, let cached = ThumbnailCache.shared.image(for: fallbackURL) {
            loadedImage = cached
            return
        }

        isLoading = true
        failed = false
        defer { isLoading = false }

        let candidates = [url, fallbackURL].compactMap { $0 }
        for candidate in candidates {
            for attempt in 0..<2 {
                do {
                    var request = URLRequest(url: candidate)
                    request.timeoutInterval = 15
                    let (data, response) = try await URLSession.shared.data(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        if http.statusCode == 404 { break }
                        continue
                    }
                    if let image = NSImage(data: data) {
                        ThumbnailCache.shared.store(image, data: data, for: candidate)
                        loadedImage = image
                        return
                    }
                } catch {
                    if attempt == 0 {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                    }
                }
            }
        }
        failed = true
    }
}
