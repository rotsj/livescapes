import AppKit
import AVFoundation
import Foundation

enum OfficialApplyTarget {
    case desktop
    case lockScreen
    case both
}

enum LockScreenInstaller {
    private static let customCategoryID = "LS000000-0000-4000-8000-000000000001"
    private static let customSubcategoryID = "LS000000-0000-4000-8000-000000000002"

    private static var wallpaperSupportRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper", isDirectory: true)
    }

    private static var aerialsRoot: URL {
        wallpaperSupportRoot.appendingPathComponent("aerials", isDirectory: true)
    }

    private static var videosDir: URL {
        aerialsRoot.appendingPathComponent("videos", isDirectory: true)
    }

    private static var thumbnailsDir: URL {
        aerialsRoot.appendingPathComponent("thumbnails", isDirectory: true)
    }

    private static var manifestDir: URL {
        aerialsRoot.appendingPathComponent("manifest", isDirectory: true)
    }

    private static var entriesJSONURL: URL {
        manifestDir.appendingPathComponent("entries.json")
    }

    private static var indexPlistURL: URL {
        wallpaperSupportRoot.appendingPathComponent("Store/Index.plist")
    }

    static func installAsLockScreen(item: WallpaperItem, localVideoURL: URL) async throws {
        try await install(item: item, localVideoURL: localVideoURL, target: .lockScreen)
    }

    static func install(item: WallpaperItem, localVideoURL: URL, target: OfficialApplyTarget) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: videosDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: manifestDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: indexPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let assetID = item.id.uppercased()

        // 1. Copy, convert, or extend short clips (< 120s) into com.apple.wallpaper/aerials/videos/<assetID>.mov
        let destVideoURL = videosDir.appendingPathComponent("\(assetID).mov")
        if fm.fileExists(atPath: destVideoURL.path) {
            try fm.removeItem(at: destVideoURL)
        }
        let durationSeconds = try await videoDurationSeconds(url: localVideoURL)
        if durationSeconds > 0 && durationSeconds < 120 {
            try await extendAndExportMOV(sourceURL: localVideoURL, destinationURL: destVideoURL, targetDuration: 180)
        } else if localVideoURL.pathExtension.lowercased() == "mov" {
            try fm.copyItem(at: localVideoURL, to: destVideoURL)
        } else {
            try await convertToMOV(sourceURL: localVideoURL, destinationURL: destVideoURL)
        }

        // 2. Ensure PNG thumbnail exists in com.apple.wallpaper/aerials/thumbnails/<assetID>.png
        let destThumbURL = thumbnailsDir.appendingPathComponent("\(assetID).png")
        if !fm.fileExists(atPath: destThumbURL.path) {
            if let existingThumb = item.localThumbnailPath, fm.fileExists(atPath: existingThumb) {
                try fm.copyItem(at: URL(fileURLWithPath: existingThumb), to: destThumbURL)
            } else {
                try await generateThumbnail(for: destVideoURL, savingTo: destThumbURL)
            }
        }

        // 3. Ensure entries.json exists and register custom/web asset if needed
        try ensureEntriesJSONAndRegisterIfNeeded(
            assetID: assetID,
            title: item.title,
            needsRegistration: item.isCustom || item.source == .externalFeed,
            videoURL: destVideoURL,
            thumbURL: destThumbURL
        )

        // 4. Update Store/Index.plist
        try updateIndexPlist(assetID: assetID, target: target)

        // 5. Restart WallpaperAgent so macOS applies the change immediately
        restartWallpaperAgent()
    }

    private static func ensureEntriesJSONAndRegisterIfNeeded(
        assetID: String,
        title: String,
        needsRegistration: Bool,
        videoURL: URL,
        thumbURL: URL
    ) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: entriesJSONURL.path) {
            let systemEntries = "/System/Library/ExtensionKit/Extensions/WallpaperAerialsExtension.appex/Contents/Resources/entries.json"
            if fm.fileExists(atPath: systemEntries) {
                try fm.copyItem(atPath: systemEntries, toPath: entriesJSONURL.path)
            } else {
                let empty: [String: Any] = ["version": 1, "categories": [], "assets": []]
                let data = try JSONSerialization.data(withJSONObject: empty, options: [.prettyPrinted])
                try data.write(to: entriesJSONURL, options: .atomic)
            }
        }

        // One-time backup
        let backupURL = entriesJSONURL.appendingPathExtension("bak")
        if !fm.fileExists(atPath: backupURL.path) {
            try? fm.copyItem(at: entriesJSONURL, to: backupURL)
        }

        let data = try Data(contentsOf: entriesJSONURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "LiveScapes", code: 20, userInfo: [NSLocalizedDescriptionKey: "Invalid entries.json format."])
        }

        var assets = root["assets"] as? [[String: Any]] ?? []
        let alreadyInManifest = assets.contains { ($0["id"] as? String)?.uppercased() == assetID }

        if !needsRegistration && alreadyInManifest {
            return
        }

        var categories = root["categories"] as? [[String: Any]] ?? []
        if !categories.contains(where: { ($0["id"] as? String) == customCategoryID }) {
            let customCat: [String: Any] = [
                "id": customCategoryID,
                "localizedDescriptionKey": "LiveScapes",
                "localizedNameKey": "LiveScapes",
                "preferredOrder": 0,
                "previewImage": thumbURL.absoluteString,
                "representativeAssetID": assetID,
                "subcategories": [
                    [
                        "id": customSubcategoryID,
                        "localizedDescriptionKey": "LiveScapes",
                        "localizedNameKey": "LiveScapes",
                        "preferredOrder": 0,
                        "previewImage": thumbURL.absoluteString,
                        "representativeAssetID": assetID
                    ]
                ]
            ]
            categories.insert(customCat, at: 0)
            root["categories"] = categories
        }

        let newAsset: [String: Any] = [
            "id": assetID,
            "accessibilityLabel": title,
            "localizedNameKey": title,
            "categories": [customCategoryID],
            "subcategories": [customSubcategoryID],
            "includeInShuffle": true,
            "showInTopLevel": true,
            "preferredOrder": 0,
            "pointsOfInterest": ["0": "LS_\(assetID.prefix(8))_0"],
            "shotID": "LS_\(assetID.prefix(8))",
            "previewImage": thumbURL.absoluteString,
            "url-4K-SDR-240FPS": videoURL.absoluteString
        ]

        assets.removeAll { ($0["id"] as? String)?.uppercased() == assetID }
        assets.append(newAsset)
        root["assets"] = assets

        let updatedData = try JSONSerialization.data(withJSONObject: root, options: [])
        try updatedData.write(to: entriesJSONURL, options: .atomic)
    }

    private static func updateIndexPlist(assetID: String, target: OfficialApplyTarget) throws {
        let fm = FileManager.default
        var plistDict: [String: Any] = [:]

        if fm.fileExists(atPath: indexPlistURL.path) {
            let backupURL = indexPlistURL.appendingPathExtension("bak")
            if !fm.fileExists(atPath: backupURL.path) {
                try? fm.copyItem(at: indexPlistURL, to: backupURL)
            }
            let existingData = try Data(contentsOf: indexPlistURL)
            if let loaded = try PropertyListSerialization.propertyList(from: existingData, options: [], format: nil) as? [String: Any] {
                plistDict = loaded
            }
        }

        let configData = try PropertyListSerialization.data(
            fromPropertyList: ["assetID": assetID],
            format: .binary,
            options: 0
        )

        let encodedOptionsData = try PropertyListSerialization.data(
            fromPropertyList: [
                "values": [
                    "aerialShuffleFrequency": [
                        "picker": [
                            "_0": ["id": "shuffle_never"]
                        ]
                    ]
                ]
            ],
            format: .binary,
            options: 0
        )

        let now = Date()
        let contentEntry: [String: Any] = [
            "Content": [
                "Choices": [
                    [
                        "Configuration": configData,
                        "Files": [] as [Any],
                        "Provider": "com.apple.wallpaper.choice.aerials"
                    ]
                ],
                "EncodedOptionValues": encodedOptionsData
            ],
            "LastSet": now,
            "LastUse": now
        ]

        let section: [String: Any]
        switch target {
        case .both:
            section = [
                "Linked": contentEntry,
                "Type": "linked"
            ]
        case .desktop:
            let existing = (plistDict["AllSpacesAndDisplays"] as? [String: Any])
                ?? (plistDict["SystemDefault"] as? [String: Any])
            let existingIdle = existing?["Idle"] ?? existing?["Linked"] ?? contentEntry
            section = [
                "Desktop": contentEntry,
                "Idle": existingIdle,
                "Type": "individual"
            ]
        case .lockScreen:
            let existing = (plistDict["AllSpacesAndDisplays"] as? [String: Any])
                ?? (plistDict["SystemDefault"] as? [String: Any])
            let existingDesktop = existing?["Desktop"] ?? existing?["Linked"] ?? contentEntry
            section = [
                "Desktop": existingDesktop,
                "Idle": contentEntry,
                "Type": "individual"
            ]
        }

        plistDict["AllSpacesAndDisplays"] = section
        plistDict["SystemDefault"] = section
        // Clear per-display and per-space overrides so AllSpacesAndDisplays takes effect everywhere
        plistDict["Displays"] = [String: Any]()
        plistDict["Spaces"] = [String: Any]()

        let outData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .binary, options: 0)
        try outData.write(to: indexPlistURL, options: .atomic)
    }

    private static func restartWallpaperAgent() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["WallpaperAgent"]
        try? task.run()
        task.waitUntilExit()
    }

    private static func generateThumbnail(for videoURL: URL, savingTo thumbURL: URL) async throws {
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
            throw NSError(domain: "LiveScapes", code: 21, userInfo: [NSLocalizedDescriptionKey: "Failed to encode thumbnail PNG."])
        }
        try pngData.write(to: thumbURL, options: .atomic)
    }

    private static func convertToMOV(sourceURL: URL, destinationURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
                ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "LiveScapes", code: 22, userInfo: [NSLocalizedDescriptionKey: "Could not create AVAssetExportSession."])
        }
        session.outputURL = destinationURL
        session.outputFileType = .mov
        await session.export()
        if let error = session.error {
            throw error
        }
        guard session.status == .completed else {
            throw NSError(domain: "LiveScapes", code: 23, userInfo: [NSLocalizedDescriptionKey: "MOV export did not complete."])
        }
    }

    private static func videoDurationSeconds(url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    /// Repeats short clips in an AVMutableComposition using passthrough export so Lock Screen playback doesn't stop after a few seconds.
    private static func extendAndExportMOV(sourceURL: URL, destinationURL: URL, targetDuration: Double) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let clipSeconds = CMTimeGetSeconds(duration)
        guard clipSeconds > 0 else {
            try await convertToMOV(sourceURL: sourceURL, destinationURL: destinationURL)
            return
        }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            try await convertToMOV(sourceURL: sourceURL, destinationURL: destinationURL)
            return
        }

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            try await convertToMOV(sourceURL: sourceURL, destinationURL: destinationURL)
            return
        }

        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        compVideoTrack.preferredTransform = preferredTransform

        let trackRange = try await sourceVideoTrack.load(.timeRange)
        let trackDuration = CMTimeGetSeconds(trackRange.duration) > 0 ? trackRange.duration : duration
        let effectiveSeconds = max(CMTimeGetSeconds(trackDuration), clipSeconds)

        let repeatCount = max(2, min(60, Int(ceil(targetDuration / effectiveSeconds))))
        var insertTime = CMTime.zero
        let timeRange = CMTimeRange(start: trackRange.start, duration: trackDuration)

        for _ in 0..<repeatCount {
            try compVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: insertTime)
            insertTime = CMTimeAdd(insertTime, trackDuration)
        }

        try await exportMOV(asset: composition, destinationURL: destinationURL)
    }

    private static func exportMOV(asset: AVAsset, destinationURL: URL) async throws {
        let presets = [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        var lastError: Error?

        for preset in presets {
            try? FileManager.default.removeItem(at: destinationURL)
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
                continue
            }
            session.outputURL = destinationURL
            session.outputFileType = .mov
            await session.export()

            if session.status == .completed {
                return
            }
            lastError = session.error
        }

        if let lastError {
            throw lastError
        }
        throw NSError(domain: "LiveScapes", code: 25, userInfo: [NSLocalizedDescriptionKey: "Extended MOV export failed."])
    }
}
