import AppKit
import AVFoundation
import Foundation

@MainActor
final class LocalLibraryStore: ObservableObject {
    @Published private(set) var customItems: [WallpaperItem] = []

    init() {
        load()
    }

    func load() {
        let url = AppPaths.customMetadataFile
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            customItems = []
            return
        }
        guard let decoded = try? JSONDecoder().decode([WallpaperItem].self, from: data) else {
            customItems = []
            return
        }
        customItems = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(customItems) else { return }
        try? data.write(to: AppPaths.customMetadataFile, options: .atomic)
    }

    func importVideo(from sourceURL: URL, title: String, category: String = "Custom") async throws -> WallpaperItem {
        let id = UUID().uuidString.uppercased()
        let destVideoURL = AppPaths.customLibraryDirectory.appendingPathComponent("\(id).mov")
        let destThumbURL = AppPaths.customLibraryDirectory.appendingPathComponent("\(id).png")

        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        if sourceURL.pathExtension.lowercased() == "mov" {
            if FileManager.default.fileExists(atPath: destVideoURL.path) {
                try FileManager.default.removeItem(at: destVideoURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destVideoURL)
        } else {
            try await convertToMOV(sourceURL: sourceURL, destinationURL: destVideoURL)
        }

        try await generateThumbnail(for: destVideoURL, savingTo: destThumbURL)

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = WallpaperItem(
            id: id,
            title: cleanTitle.isEmpty ? sourceURL.deletingPathExtension().lastPathComponent : cleanTitle,
            category: category,
            source: .custom,
            previewImageURL: nil,
            remoteVideoURL: nil,
            localVideoPath: destVideoURL.path,
            localThumbnailPath: destThumbURL.path,
            isCustom: true,
            createdAt: Date()
        )

        customItems.insert(item, at: 0)
        save()
        return item
    }

    func saveOnlineWallpaper(_ sourceItem: WallpaperItem, downloadedVideoURL: URL) async throws -> WallpaperItem {
        return try await importVideo(
            from: downloadedVideoURL,
            title: sourceItem.title,
            category: sourceItem.category
        )
    }

    func isSavedLocally(_ item: WallpaperItem) -> Bool {
        if item.isCustom { return true }
        return customItems.contains { $0.title == item.title && $0.category == item.category }
    }

    func delete(_ item: WallpaperItem) {
        if let vPath = item.localVideoPath {
            try? FileManager.default.removeItem(atPath: vPath)
        }
        if let tPath = item.localThumbnailPath {
            try? FileManager.default.removeItem(atPath: tPath)
        }
        customItems.removeAll { $0.id == item.id }
        save()
    }

    private func convertToMOV(sourceURL: URL, destinationURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let isPassthroughCompatible = await AVAssetExportSession.compatibility(
            ofExportPreset: AVAssetExportPresetPassthrough,
            with: asset,
            outputFileType: .mov
        )
        let preset = isPassthroughCompatible
            ? AVAssetExportPresetPassthrough
            : AVAssetExportPresetHighestQuality

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw NSError(domain: "LiveScapes", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create AVAssetExportSession for video."])
        }

        session.outputURL = destinationURL
        session.outputFileType = .mov
        session.shouldOptimizeForNetworkUse = false

        await session.export()

        if let error = session.error {
            throw error
        }
        guard session.status == .completed else {
            throw NSError(domain: "LiveScapes", code: 2, userInfo: [NSLocalizedDescriptionKey: "Video conversion did not complete (status: \(session.status.rawValue))."])
        }
    }

    func generateThumbnail(for videoURL: URL, savingTo thumbURL: URL) async throws {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 540)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        let cgImage: CGImage
        do {
            cgImage = try await generator.image(at: time).image
        } catch {
            cgImage = try await generator.image(at: .zero).image
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "LiveScapes", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG thumbnail."])
        }
        try pngData.write(to: thumbURL, options: .atomic)
    }
}
