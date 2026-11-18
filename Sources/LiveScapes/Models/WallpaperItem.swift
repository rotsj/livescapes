import Foundation

enum WallpaperSource: String, Codable, Hashable {
    case appleAerial
    case externalFeed
    case custom
}

struct WallpaperItem: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var category: String
    var source: WallpaperSource
    var feedID: UUID? = nil
    var feedName: String? = nil
    var previewImageURL: URL?
    var fallbackThumbnailURL: URL? = nil
    var remoteVideoURL: URL?
    var fallbackVideoURLs: [URL]? = nil
    var localVideoPath: String?
    var localThumbnailPath: String?
    var isCustom: Bool
    var createdAt: Date

    var effectiveThumbnailURL: URL? {
        if let localThumbnailPath, FileManager.default.fileExists(atPath: localThumbnailPath) {
            return URL(fileURLWithPath: localThumbnailPath)
        }
        return previewImageURL
    }

    var effectiveVideoURL: URL? {
        if let localVideoPath, FileManager.default.fileExists(atPath: localVideoPath) {
            return URL(fileURLWithPath: localVideoPath)
        }
        return remoteVideoURL
    }

    var isDownloadedLocally: Bool {
        if let localVideoPath {
            return FileManager.default.fileExists(atPath: localVideoPath)
        }
        return false
    }
}
