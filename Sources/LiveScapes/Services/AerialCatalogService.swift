import Foundation

enum AerialCatalogService {
    private struct RawCatalog: Decodable {
        struct RawCategory: Decodable {
            let id: String
            let localizedNameKey: String?
            let subcategories: [RawSubcategory]?
        }
        struct RawSubcategory: Decodable {
            let id: String
            let localizedNameKey: String?
        }
        struct RawAsset: Decodable {
            let id: String
            let accessibilityLabel: String?
            let localizedNameKey: String?
            let previewImage: String?
            let categories: [String]?
            let subcategories: [String]?
            let url4KSDR240: String?
            let preferredOrder: Int?

            enum CodingKeys: String, CodingKey {
                case id, accessibilityLabel, localizedNameKey, previewImage, categories, subcategories, preferredOrder
                case url4KSDR240 = "url-4K-SDR-240FPS"
            }
        }

        let categories: [RawCategory]?
        let assets: [RawAsset]?
    }

    static func loadGallery() -> [WallpaperItem] {
        let candidates = [
            "/System/Library/ExtensionKit/Extensions/WallpaperAerialsExtension.appex/Contents/Resources/entries.json",
            NSHomeDirectory() + "/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json"
        ]

        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let raw = try? JSONDecoder().decode(RawCatalog.self, from: data) else {
            return []
        }

        var categoryNames: [String: String] = [:]
        for cat in raw.categories ?? [] {
            let cleanCat = cleanCategoryKey(cat.localizedNameKey ?? "Aerials")
            categoryNames[cat.id] = cleanCat
            for sub in cat.subcategories ?? [] {
                let cleanSub = cleanCategoryKey(sub.localizedNameKey ?? cleanCat)
                categoryNames[sub.id] = cleanSub
            }
        }

        let cacheDir = AppPaths.cacheDirectory
        let systemAerialVideosDir = NSHomeDirectory() + "/Library/Application Support/com.apple.wallpaper/aerials/videos"

        var items: [WallpaperItem] = []
        for asset in raw.assets ?? [] {
            // Skip injected custom entries if reading from user manifest
            if asset.id.hasPrefix("BD000000-") { continue }
            guard let urlString = asset.url4KSDR240,
                  let videoURL = URL(string: urlString),
                  urlString.hasPrefix("http") else { continue }

            let title = asset.accessibilityLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? cleanCategoryKey(asset.localizedNameKey ?? asset.id)

            let catName = asset.subcategories?.compactMap { categoryNames[$0] }.first
                ?? asset.categories?.compactMap { categoryNames[$0] }.first
                ?? "Aerials"

            let previewURL = asset.previewImage.flatMap { URL(string: $0) }

            let cachedPath = cacheDir.appendingPathComponent("\(asset.id).mov").path
            let systemCachedPath = "\(systemAerialVideosDir)/\(asset.id).mov"
            let localPath: String? =
                FileManager.default.fileExists(atPath: cachedPath) ? cachedPath :
                (FileManager.default.fileExists(atPath: systemCachedPath) ? systemCachedPath : nil)

            items.append(WallpaperItem(
                id: asset.id,
                title: title,
                category: catName,
                source: .appleAerial,
                previewImageURL: previewURL,
                remoteVideoURL: videoURL,
                localVideoPath: localPath,
                localThumbnailPath: nil,
                isCustom: false,
                createdAt: Date()
            ))
        }

        return items
    }

    private static func cleanCategoryKey(_ key: String) -> String {
        var result = key
            .replacingOccurrences(of: "AerialSubcategoryDescription", with: "")
            .replacingOccurrences(of: "AerialSubcategory", with: "")
            .replacingOccurrences(of: "AerialCategory", with: "")
        if result.isEmpty { result = "Aerials" }
        return result
    }
}
