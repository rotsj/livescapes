import Foundation

enum FeedFormat: String, Codable, CaseIterable, Identifiable {
    case jsonAPI = "json"
    case webPattern = "pattern"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jsonAPI: return "JSON API / Manifest"
        case .webPattern: return "Web Sitemap / Pattern"
        }
    }
}

struct WallpaperFeedConfig: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var url: String
    var format: FeedFormat = .jsonAPI
    var isEnabled: Bool = true

    // Optional JSON API / Manifest overrides
    var itemsKey: String? = nil
    var nextCursorKey: String? = nil
    var cursorParam: String? = nil
    var limitParam: String? = nil
    var pageLimit: Int? = nil

    // Optional Web Pattern / Sitemap overrides
    var regexPattern: String? = nil
    var videoURLTemplate: String? = nil
    var fallbackVideoTemplates: [String]? = nil
    var previewURLTemplate: String? = nil
    var fallbackPreviewTemplates: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, url, format, isEnabled
        case itemsKey, nextCursorKey, cursorParam, limitParam, pageLimit
        case regexPattern, videoURLTemplate, fallbackVideoTemplates, previewURLTemplate, fallbackPreviewTemplates
    }

    init(
        id: UUID = UUID(),
        name: String,
        url: String,
        format: FeedFormat = .jsonAPI,
        isEnabled: Bool = true,
        itemsKey: String? = nil,
        nextCursorKey: String? = nil,
        cursorParam: String? = nil,
        limitParam: String? = nil,
        pageLimit: Int? = nil,
        regexPattern: String? = nil,
        videoURLTemplate: String? = nil,
        fallbackVideoTemplates: [String]? = nil,
        previewURLTemplate: String? = nil,
        fallbackPreviewTemplates: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.format = format
        self.isEnabled = isEnabled
        self.itemsKey = itemsKey
        self.nextCursorKey = nextCursorKey
        self.cursorParam = cursorParam
        self.limitParam = limitParam
        self.pageLimit = pageLimit
        self.regexPattern = regexPattern
        self.videoURLTemplate = videoURLTemplate
        self.fallbackVideoTemplates = fallbackVideoTemplates
        self.previewURLTemplate = previewURLTemplate
        self.fallbackPreviewTemplates = fallbackPreviewTemplates
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(String.self, forKey: .url)
        format = try c.decodeIfPresent(FeedFormat.self, forKey: .format) ?? .jsonAPI
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        itemsKey = try c.decodeIfPresent(String.self, forKey: .itemsKey)
        nextCursorKey = try c.decodeIfPresent(String.self, forKey: .nextCursorKey)
        cursorParam = try c.decodeIfPresent(String.self, forKey: .cursorParam)
        limitParam = try c.decodeIfPresent(String.self, forKey: .limitParam)
        pageLimit = try c.decodeIfPresent(Int.self, forKey: .pageLimit)
        regexPattern = try c.decodeIfPresent(String.self, forKey: .regexPattern)
        videoURLTemplate = try c.decodeIfPresent(String.self, forKey: .videoURLTemplate)
        fallbackVideoTemplates = try c.decodeIfPresent([String].self, forKey: .fallbackVideoTemplates)
        previewURLTemplate = try c.decodeIfPresent(String.self, forKey: .previewURLTemplate)
        fallbackPreviewTemplates = try c.decodeIfPresent([String].self, forKey: .fallbackPreviewTemplates)
    }
}

struct FeedPageResult {
    let items: [WallpaperItem]
    let nextCursor: String?
}

@MainActor
final class FeedStore: ObservableObject {
    @Published var feeds: [WallpaperFeedConfig] = [] {
        didSet { save() }
    }

    private static var configURL: URL {
        AppPaths.appSupportDirectory.appendingPathComponent("feeds.json")
    }

    init() {
        load()
    }

    func add(_ feed: WallpaperFeedConfig) {
        feeds.append(feed)
    }

    func update(_ feed: WallpaperFeedConfig) {
        guard let idx = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        feeds[idx] = feed
    }

    func delete(_ feed: WallpaperFeedConfig) {
        feeds.removeAll { $0.id == feed.id }
    }

    func importConfigJSON(_ jsonString: String) throws -> Int {
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "LiveScapes", code: 60, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 text."])
        }
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([WallpaperFeedConfig].self, from: data) {
            feeds.append(contentsOf: list)
            return list.count
        }
        let single = try decoder.decode(WallpaperFeedConfig.self, from: data)
        feeds.append(single)
        return 1
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: Self.configURL.path),
              let data = try? Data(contentsOf: Self.configURL),
              let decoded = try? JSONDecoder().decode([WallpaperFeedConfig].self, from: data) else {
            feeds = []
            return
        }
        feeds = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(feeds) else { return }
        try? data.write(to: Self.configURL, options: .atomic)
    }
}

enum WallpaperFeedClient {
    static func fetchAllPages(feed: WallpaperFeedConfig, maxPages: Int = 50) async throws -> FeedPageResult {
        var allItems: [WallpaperItem] = []
        var seenIDs = Set<String>()
        var cursor: String? = nil
        var pages = 0

        repeat {
            let page = try await fetchPage(feed: feed, cursor: cursor)
            pages += 1
            for item in page.items where seenIDs.insert(item.id).inserted {
                allItems.append(item)
            }
            cursor = page.nextCursor
            if page.items.isEmpty { break }
        } while cursor != nil && pages < maxPages

        return FeedPageResult(items: allItems, nextCursor: cursor)
    }

    static func fetchPage(feed: WallpaperFeedConfig, cursor: String? = nil) async throws -> FeedPageResult {
        switch feed.format {
        case .jsonAPI:
            return try await fetchJSONFeed(feed: feed, cursor: cursor)
        case .webPattern:
            return try await fetchPatternFeed(feed: feed)
        }
    }

    private static func fetchJSONFeed(feed: WallpaperFeedConfig, cursor: String?) async throws -> FeedPageResult {
        guard var components = URLComponents(string: feed.url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NSError(domain: "LiveScapes", code: 61, userInfo: [NSLocalizedDescriptionKey: "Invalid URL for feed “\(feed.name)”."])
        }

        var queryItems = components.queryItems ?? []
        if let limit = feed.pageLimit, limit > 0 {
            let limitName = (feed.limitParam?.isEmpty == false) ? feed.limitParam! : "limit"
            if !queryItems.contains(where: { $0.name == limitName }) {
                queryItems.append(URLQueryItem(name: limitName, value: String(limit)))
            }
        }
        if let cursor, !cursor.isEmpty {
            let cursorName = (feed.cursorParam?.isEmpty == false) ? feed.cursorParam! : "cursor"
            queryItems.removeAll { $0.name == cursorName }
            queryItems.append(URLQueryItem(name: cursorName, value: cursor))
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let requestURL = components.url else {
            throw NSError(domain: "LiveScapes", code: 62, userInfo: [NSLocalizedDescriptionKey: "Could not construct request URL for “\(feed.name)”."])
        }

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await AppNetwork.session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "LiveScapes", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Feed “\(feed.name)” returned HTTP \(http.statusCode)."])
        }

        let json = try JSONSerialization.jsonObject(with: data)
        let rawItems: [[String: Any]]
        var nextCursor: String? = nil

        if let array = json as? [[String: Any]] {
            rawItems = array
        } else if let dict = json as? [String: Any] {
            let candidateKeys = [feed.itemsKey, "wallpapers", "items", "data", "results", "entries", "assets"]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            if let key = candidateKeys.first(where: { dict[$0] is [[String: Any]] }),
               let arr = dict[key] as? [[String: Any]] {
                rawItems = arr
            } else {
                rawItems = []
            }

            let cursorKeys = [feed.nextCursorKey, "nextCursor", "next_cursor", "cursor", "next"]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            for key in cursorKeys {
                if let val = dict[key] as? String, !val.isEmpty {
                    nextCursor = val
                    break
                }
            }
        } else {
            rawItems = []
        }

        let cacheDir = AppPaths.cacheDirectory
        let fm = FileManager.default

        let items: [WallpaperItem] = rawItems.compactMap { entry in
            guard let videoStr = firstString(in: entry, keys: ["videoUrl", "video_url", "video", "url", "streamUrl", "url-4K-SDR-240FPS"]),
                  let videoURL = URL(string: videoStr) else {
                return nil
            }
            let itemID = firstString(in: entry, keys: ["id", "uuid", "slug"]) ?? UUID().uuidString
            let title = (firstString(in: entry, keys: ["title", "name", "label", "accessibilityLabel"]) ?? itemID)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rawCat = firstString(in: entry, keys: ["category", "group", "tag"]) ?? "Uncategorized"
            let category = rawCat.isEmpty ? "Uncategorized" : rawCat.capitalized
            let previewURL = firstString(in: entry, keys: ["thumbnailUrl", "thumbnail_url", "thumbnail", "previewImage", "preview_image", "previewUrl"])
                .flatMap { URL(string: $0) }

            let cachedMOV = cacheDir.appendingPathComponent("\(itemID).mov").path
            let cachedMP4 = cacheDir.appendingPathComponent("\(itemID).mp4").path
            let localPath = fm.fileExists(atPath: cachedMOV) ? cachedMOV :
                (fm.fileExists(atPath: cachedMP4) ? cachedMP4 : nil)

            return WallpaperItem(
                id: itemID,
                title: title,
                category: category,
                source: .externalFeed,
                feedID: feed.id,
                feedName: feed.name,
                previewImageURL: previewURL,
                remoteVideoURL: videoURL,
                localVideoPath: localPath,
                localThumbnailPath: nil,
                isCustom: false,
                createdAt: Date()
            )
        }

        return FeedPageResult(items: items, nextCursor: nextCursor)
    }

    private static func fetchPatternFeed(feed: WallpaperFeedConfig) async throws -> FeedPageResult {
        guard let url = URL(string: feed.url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NSError(domain: "LiveScapes", code: 63, userInfo: [NSLocalizedDescriptionKey: "Invalid URL for feed “\(feed.name)”."])
        }
        guard let pattern = feed.regexPattern, !pattern.isEmpty,
              let videoTemplate = feed.videoURLTemplate, !videoTemplate.isEmpty else {
            throw NSError(domain: "LiveScapes", code: 64, userInfo: [NSLocalizedDescriptionKey: "Pattern feed “\(feed.name)” requires a regex pattern and video URL template."])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await AppNetwork.session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "LiveScapes", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Feed “\(feed.name)” returned HTTP \(http.statusCode)."])
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return FeedPageResult(items: [], nextCursor: nil)
        }

        let items = try await Task.detached(priority: .userInitiated) {
            let regex = try NSRegularExpression(pattern: pattern)
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = regex.matches(in: text, range: nsRange)

            let cacheDir = AppPaths.cacheDirectory
            let fm = FileManager.default
            var seenIDs = Set<String>()
            var result: [WallpaperItem] = []

            for match in matches {
                let rawCat: String
                let rawSlug: String
                let itemID: String

                if match.numberOfRanges >= 4,
                   let r1 = Range(match.range(at: 1), in: text),
                   let r2 = Range(match.range(at: 2), in: text),
                   let r3 = Range(match.range(at: 3), in: text) {
                    rawCat = String(text[r1])
                    rawSlug = String(text[r2])
                    itemID = String(text[r3])
                } else if match.numberOfRanges >= 2,
                          let r1 = Range(match.range(at: 1), in: text) {
                    rawCat = "General"
                    rawSlug = ""
                    itemID = String(text[r1])
                } else {
                    continue
                }

                guard seenIDs.insert(itemID.lowercased()).inserted else { continue }

                let category = rawCat.replacingOccurrences(of: "-", with: " ").capitalized
                let rawTitle = rawSlug
                    .split(separator: "-")
                    .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                    .joined(separator: " ")
                let title = rawTitle.isEmpty ? "\(category) \(itemID.prefix(6))" : rawTitle

                guard let videoURL = expandTemplate(videoTemplate, id: itemID, slug: rawSlug, category: rawCat) else {
                    continue
                }
                let fallbackVideos = (feed.fallbackVideoTemplates ?? []).compactMap {
                    expandTemplate($0, id: itemID, slug: rawSlug, category: rawCat)
                }
                let previewURL = feed.previewURLTemplate.flatMap {
                    expandTemplate($0, id: itemID, slug: rawSlug, category: rawCat)
                }
                let fallbackPreview = (feed.fallbackPreviewTemplates ?? []).compactMap {
                    expandTemplate($0, id: itemID, slug: rawSlug, category: rawCat)
                }.first

                let cachedMP4 = cacheDir.appendingPathComponent("\(itemID).mp4").path
                let cachedMOV = cacheDir.appendingPathComponent("\(itemID).mov").path
                let localPath = fm.fileExists(atPath: cachedMOV) ? cachedMOV :
                    (fm.fileExists(atPath: cachedMP4) ? cachedMP4 : nil)

                result.append(WallpaperItem(
                    id: itemID,
                    title: title,
                    category: category,
                    source: .externalFeed,
                    feedID: feed.id,
                    feedName: feed.name,
                    previewImageURL: previewURL,
                    fallbackThumbnailURL: fallbackPreview,
                    remoteVideoURL: videoURL,
                    fallbackVideoURLs: fallbackVideos.isEmpty ? nil : fallbackVideos,
                    localVideoPath: localPath,
                    localThumbnailPath: nil,
                    isCustom: false,
                    createdAt: Date()
                ))
            }
            return result
        }.value

        return FeedPageResult(items: items, nextCursor: nil)
    }

    private static func firstString(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func expandTemplate(_ template: String, id: String, slug: String, category: String) -> URL? {
        let expanded = template
            .replacingOccurrences(of: "{id}", with: id)
            .replacingOccurrences(of: "{id_upper}", with: id.uppercased())
            .replacingOccurrences(of: "{id_lower}", with: id.lowercased())
            .replacingOccurrences(of: "{slug}", with: slug)
            .replacingOccurrences(of: "{category}", with: category)
        return URL(string: expanded)
    }
}
