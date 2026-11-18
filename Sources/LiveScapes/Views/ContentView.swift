import AppKit
import SwiftUI

enum SidebarFilter: Hashable {
    case all
    case myCustom
    case solar
    case allFeeds
    case feed(UUID)
    case feedCategory(UUID, String)
    case allAerials
    case aerialCategory(String)
}

struct ContentView: View {
    @ObservedObject var desktopManager: DesktopWallpaperManager
    @ObservedObject var localStore: LocalLibraryStore
    @ObservedObject var downloader: VideoDownloader
    @ObservedObject var solarManager: SolarCollectionManager
    @ObservedObject var feedStore: FeedStore

    @AppStorage("useContinuousDesktopOverlay") private var useContinuousDesktopOverlay: Bool = false

    @State private var aerialItems: [WallpaperItem] = []
    @State private var feedItems: [UUID: [WallpaperItem]] = [:]
    @State private var feedNextCursors: [UUID: String] = [:]
    @State private var selectedFilter: SidebarFilter = .all
    @State private var selectedItem: WallpaperItem?
    @State private var searchText: String = ""
    @State private var showCreateSheet: Bool = false
    @State private var showFeedsSheet: Bool = false
    @State private var statusMessage: String?
    @State private var isWorking: Bool = false
    @State private var isLoadingFeeds: Bool = false
    @State private var currentPage: Int = 0
    @State private var expandedFeedIDs: Set<UUID> = []
    @State private var isAerialsExpanded: Bool = false

    private let pageSize: Int = 36

    private var allFeedItems: [WallpaperItem] {
        feedStore.feeds.filter(\.isEnabled).flatMap { feedItems[$0.id] ?? [] }
    }

    private var allItems: [WallpaperItem] {
        localStore.customItems + allFeedItems + aerialItems
    }

    private func categories(for feedID: UUID) -> [String] {
        Array(Set((feedItems[feedID] ?? []).map(\.category))).sorted()
    }

    private func categoryCount(for feedID: UUID, category: String) -> Int {
        (feedItems[feedID] ?? []).filter { $0.category == category }.count
    }

    private var aerialCategories: [String] {
        Array(Set(aerialItems.map(\.category))).sorted()
    }

    private func aerialCategoryCount(_ category: String) -> Int {
        aerialItems.filter { $0.category == category }.count
    }

    private var filteredItems: [WallpaperItem] {
        let base: [WallpaperItem]
        switch selectedFilter {
        case .all:
            base = allItems
        case .myCustom, .solar:
            base = localStore.customItems
        case .allFeeds:
            base = allFeedItems
        case .feed(let feedID):
            base = feedItems[feedID] ?? []
        case .feedCategory(let feedID, let cat):
            base = (feedItems[feedID] ?? []).filter { $0.category == cat }
        case .allAerials:
            base = aerialItems
        case .aerialCategory(let cat):
            base = aerialItems.filter { $0.category == cat }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return base }
        return base.filter {
            $0.title.lowercased().contains(query) || $0.category.lowercased().contains(query)
        }
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(filteredItems.count) / Double(pageSize))))
    }

    private var pagedItems: [WallpaperItem] {
        let safePage = min(max(0, currentPage), totalPages - 1)
        let start = safePage * pageSize
        guard start < filteredItems.count else { return [] }
        let end = min(start + pageSize, filteredItems.count)
        return Array(filteredItems[start..<end])
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedFilter) {
                Section("Library") {
                    Label("All Wallpapers", systemImage: "sparkles.tv")
                        .tag(SidebarFilter.all)
                    Label("My Live Wallpapers (\(localStore.customItems.count))", systemImage: "film.stack")
                        .tag(SidebarFilter.myCustom)
                    Label("Solar", systemImage: solarManager.config.isEnabled ? "sun.max.fill" : "sun.horizon")
                        .tag(SidebarFilter.solar)
                }

                Section("External Feeds") {
                    if feedStore.feeds.filter(\.isEnabled).isEmpty {
                        Button {
                            showFeedsSheet = true
                        } label: {
                            Label("Configure Feeds…", systemImage: "plus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    } else {
                        Label("All Feeds (\(allFeedItems.count))", systemImage: "globe")
                            .tag(SidebarFilter.allFeeds)
                        ForEach(feedStore.feeds.filter(\.isEnabled)) { feed in
                            let count = (feedItems[feed.id] ?? []).count
                            let feedCats = categories(for: feed.id)
                            if feedCats.isEmpty {
                                Label("\(feed.name) (\(count))", systemImage: "dot.radiowaves.left.and.right")
                                    .tag(SidebarFilter.feed(feed.id))
                            } else {
                                DisclosureGroup(
                                    isExpanded: Binding(
                                        get: { expandedFeedIDs.contains(feed.id) },
                                        set: { expanded in
                                            if expanded {
                                                expandedFeedIDs.insert(feed.id)
                                            } else {
                                                expandedFeedIDs.remove(feed.id)
                                            }
                                        }
                                    )
                                ) {
                                    ForEach(feedCats, id: \.self) { category in
                                        Label("\(category) (\(categoryCount(for: feed.id, category: category)))", systemImage: "tag")
                                            .tag(SidebarFilter.feedCategory(feed.id, category))
                                    }
                                } label: {
                                    Label("\(feed.name) (\(count))", systemImage: "dot.radiowaves.left.and.right")
                                }
                                .tag(SidebarFilter.feed(feed.id))
                            }
                        }
                    }
                }

                if !aerialCategories.isEmpty {
                    Section("Apple 4K Aerials") {
                        DisclosureGroup(isExpanded: $isAerialsExpanded) {
                            ForEach(aerialCategories, id: \.self) { category in
                                Label("\(category) (\(aerialCategoryCount(category)))", systemImage: "airplane")
                                    .tag(SidebarFilter.aerialCategory(category))
                            }
                        } label: {
                            Label("All Aerials (\(aerialItems.count))", systemImage: "airplane.circle")
                        }
                        .tag(SidebarFilter.allAerials)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } content: {
            VStack(spacing: 0) {
                if selectedFilter == .solar {
                    SolarLibraryView(
                        solarManager: solarManager,
                        localStore: localStore,
                        selectedItem: $selectedItem
                    )
                } else if filteredItems.isEmpty {
                    ContentUnavailableView(
                        isLoadingFeeds ? "Loading Feeds…" : "No Wallpapers Found",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Try a different search, configure an external feed, or import a .mov/.mp4 file.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16)], spacing: 16) {
                            ForEach(pagedItems) { item in
                                WallpaperCardView(
                                    item: item,
                                    isSelected: selectedItem?.id == item.id,
                                    downloadProgress: downloader.activeDownloads[item.id]
                                )
                                .onTapGesture {
                                    selectedItem = item
                                }
                            }
                        }
                        .padding(16)
                    }

                    if filteredItems.count > pageSize || activeFeedNextCursor != nil {
                        HStack(spacing: 12) {
                            Button {
                                currentPage = max(0, currentPage - 1)
                            } label: {
                                Label("Previous", systemImage: "chevron.left")
                            }
                            .disabled(currentPage == 0)

                            Text("Page \(min(currentPage + 1, totalPages)) of \(totalPages)\(activeFeedNextCursor != nil ? "+" : "") (\(filteredItems.count) wallpapers)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()

                            Button {
                                if currentPage < totalPages - 1 {
                                    currentPage += 1
                                } else if let feedID = activeFeedID, activeFeedNextCursor != nil {
                                    Task {
                                        let prevPages = totalPages
                                        await loadMoreFeed(feedID: feedID)
                                        if totalPages > prevPages {
                                            currentPage += 1
                                        }
                                    }
                                }
                            } label: {
                                Label("Next", systemImage: "chevron.right")
                                    .labelStyle(.titleAndIcon)
                            }
                            .disabled(currentPage >= totalPages - 1 && activeFeedNextCursor == nil)

                            if let feedID = activeFeedID, activeFeedNextCursor != nil {
                                Divider().frame(height: 16)
                                Button {
                                    Task { await loadMoreFeed(feedID: feedID) }
                                } label: {
                                    if isLoadingFeeds {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label("Load More", systemImage: "plus.circle")
                                    }
                                }
                                .disabled(isLoadingFeeds)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                    }
                }

                if let statusMessage {
                    HStack(spacing: 8) {
                        if isWorking {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "info.circle")
                        }
                        Text(statusMessage)
                            .font(.caption)
                            .lineLimit(2)
                        Spacer()
                        Button("Dismiss") {
                            self.statusMessage = nil
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
            .searchable(text: $searchText, prompt: "Search wallpapers…")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if desktopManager.currentVideoURL != nil {
                        Button {
                            desktopManager.togglePlayPause()
                        } label: {
                            Label(
                                desktopManager.isPlaying ? "Pause Desktop" : "Resume Desktop",
                                systemImage: desktopManager.isPlaying ? "pause.circle" : "play.circle"
                            )
                        }
                        Button {
                            desktopManager.stop()
                            statusMessage = "Stopped desktop live wallpaper."
                        } label: {
                            Label("Stop Desktop", systemImage: "stop.circle")
                        }
                    }

                    Button {
                        showFeedsSheet = true
                    } label: {
                        Label("Configure Feeds", systemImage: "dot.radiowaves.left.and.right")
                    }

                    Button {
                        Task { await loadAllFeeds() }
                    } label: {
                        Label("Refresh Feeds", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoadingFeeds)

                    Button {
                        selectedFilter = .solar
                    } label: {
                        Label("Solar Auto-Adjust", systemImage: solarManager.config.isEnabled ? "sun.max.fill" : "sun.horizon")
                    }

                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("Create Live Wallpaper", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let item = selectedItem {
                DetailInspectorView(
                    item: item,
                    downloadProgress: downloader.activeDownloads[item.id],
                    isWorking: isWorking,
                    onApplyDesktop: {
                        Task { await apply(item: item, desktop: true, lockScreen: false) }
                    },
                    onApplyLockScreen: {
                        Task { await apply(item: item, desktop: false, lockScreen: true) }
                    },
                    onApplyBoth: {
                        Task { await apply(item: item, desktop: true, lockScreen: true) }
                    },
                    isSavedLocally: localStore.isSavedLocally(item),
                    useContinuousOverlay: $useContinuousDesktopOverlay,
                    onSaveToLocal: !item.isCustom ? {
                        Task { await saveToLocal(item: item) }
                    } : nil,
                    onDeleteCustom: item.isCustom ? {
                        localStore.delete(item)
                        if selectedItem?.id == item.id {
                            selectedItem = nil
                        }
                    } : nil
                )
            } else {
                ContentUnavailableView(
                    "Select a Wallpaper",
                    systemImage: "play.rectangle",
                    description: Text("Choose any wallpaper to preview it live and apply it to your Desktop or Lock Screen.")
                )
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateWallpaperSheet(localStore: localStore) { newItem, applyDesktop, applyLockScreen in
                selectedFilter = .myCustom
                selectedItem = newItem
                if applyDesktop || applyLockScreen {
                    Task { await apply(item: newItem, desktop: applyDesktop, lockScreen: applyLockScreen) }
                }
            }
        }
        .sheet(isPresented: $showFeedsSheet) {
            FeedManagerSheet(feedStore: feedStore) {
                Task { await loadAllFeeds() }
            }
        }
        .onChange(of: selectedItem) { _, newValue in
            solarManager.activeGallerySelection = newValue
        }
        .onAppear {
            solarManager.setContinuousOverlay(useContinuousDesktopOverlay)
            solarManager.configure(downloader: downloader, desktopManager: desktopManager)
            if aerialItems.isEmpty {
                aerialItems = AerialCatalogService.loadGallery()
            }
            if feedItems.isEmpty && !feedStore.feeds.isEmpty {
                Task { await loadAllFeeds() }
            }
            if selectedItem == nil {
                selectedItem = allItems.first
            }
        }
        .onChange(of: selectedFilter) { _, _ in
            currentPage = 0
        }
        .onChange(of: searchText) { _, _ in
            currentPage = 0
        }
        .onChange(of: useContinuousDesktopOverlay) { _, newValue in
            solarManager.setContinuousOverlay(newValue)
            if !newValue {
                desktopManager.stop()
            }
        }
    }

    private var activeFeedID: UUID? {
        switch selectedFilter {
        case .feed(let id), .feedCategory(let id, _):
            return id
        default:
            return nil
        }
    }

    private var activeFeedNextCursor: String? {
        guard let feedID = activeFeedID else { return nil }
        return feedNextCursors[feedID]
    }

    private func loadAllFeeds() async {
        let enabledFeeds = feedStore.feeds.filter(\.isEnabled)
        feedItems = feedItems.filter { id, _ in enabledFeeds.contains(where: { $0.id == id }) }
        feedNextCursors = feedNextCursors.filter { id, _ in enabledFeeds.contains(where: { $0.id == id }) }

        guard !enabledFeeds.isEmpty else { return }
        isLoadingFeeds = true
        defer { isLoadingFeeds = false }

        for feed in enabledFeeds {
            do {
                let page = try await WallpaperFeedClient.fetchAllPages(feed: feed)
                feedItems[feed.id] = page.items
                feedNextCursors[feed.id] = page.nextCursor
            } catch {
                statusMessage = "Feed “\(feed.name)” load failed: \(error.localizedDescription)"
            }
        }

        if selectedItem == nil {
            selectedItem = allItems.first
        }
    }

    private func loadMoreFeed(feedID: UUID) async {
        guard let feed = feedStore.feeds.first(where: { $0.id == feedID }),
              let cursor = feedNextCursors[feedID],
              !isLoadingFeeds else { return }
        isLoadingFeeds = true
        defer { isLoadingFeeds = false }
        do {
            let page = try await WallpaperFeedClient.fetchPage(feed: feed, cursor: cursor)
            var current = feedItems[feedID] ?? []
            let existingIDs = Set(current.map(\.id))
            current.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
            feedItems[feedID] = current
            feedNextCursors[feedID] = page.nextCursor
        } catch {
            statusMessage = "Feed “\(feed.name)” load more failed: \(error.localizedDescription)"
        }
    }

    private func saveToLocal(item: WallpaperItem) async {
        isWorking = true
        defer { isWorking = false }
        do {
            statusMessage = item.isDownloadedLocally
                ? "Saving “\(item.title)” to My Live Wallpapers…"
                : "Downloading “\(item.title)” to save locally…"
            let localURL = try await downloader.ensureLocalVideo(for: item)
            _ = try await localStore.saveOnlineWallpaper(item, downloadedVideoURL: localURL)
            statusMessage = "Saved “\(item.title)” to My Live Wallpapers."
        } catch {
            statusMessage = "Error saving locally: \(error.localizedDescription)"
        }
    }

    private func apply(item: WallpaperItem, desktop: Bool, lockScreen: Bool) async {
        isWorking = true
        defer { isWorking = false }

        do {
            statusMessage = item.isDownloadedLocally
                ? "Preparing \(item.title)…"
                : "Downloading \(item.title)…"

            let localURL = try await downloader.ensureLocalVideo(for: item)

            let target: OfficialApplyTarget
            switch (desktop, lockScreen) {
            case (true, true): target = .both
            case (true, false): target = .desktop
            case (false, true): target = .lockScreen
            case (false, false): return
            }

            statusMessage = "Installing \(item.title) via macOS WallpaperAgent…"
            try await LockScreenInstaller.install(item: item, localVideoURL: localURL, target: target)

            if desktop && useContinuousDesktopOverlay {
                desktopManager.apply(videoURL: localURL, title: item.title)
            } else if desktop {
                desktopManager.stop()
            }

            switch (desktop, lockScreen) {
            case (true, true):
                statusMessage = useContinuousDesktopOverlay
                    ? "Applied “\(item.title)” to Desktop (Continuous Loop) & Lock Screen."
                    : "Applied “\(item.title)” officially to Desktop & Lock Screen."
            case (true, false):
                statusMessage = useContinuousDesktopOverlay
                    ? "Applied “\(item.title)” to Desktop (Continuous Loop)."
                    : "Applied “\(item.title)” officially to Desktop."
            case (false, true):
                statusMessage = "Applied “\(item.title)” officially to Lock Screen."
            case (false, false):
                break
            }
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
}

private struct WallpaperCardView: View {
    let item: WallpaperItem
    let isSelected: Bool
    let downloadProgress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(height: 124)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 4) {
                    if item.isCustom {
                        BadgeView(text: "Custom", color: .purple)
                    } else if item.source == .externalFeed {
                        BadgeView(text: item.isDownloadedLocally ? "Cached" : (item.feedName ?? "Feed"), color: item.isDownloadedLocally ? .green : .blue)
                    } else if item.isDownloadedLocally {
                        BadgeView(text: "Cached", color: .green)
                    }
                }
                .padding(6)

                if let progress = downloadProgress {
                    VStack {
                        Spacer()
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .padding(8)
                            .background(.ultraThinMaterial)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.08), lineWidth: isSelected ? 2.5 : 1)
            )

            Text(item.title)
                .font(.headline)
                .lineLimit(1)
            Text(item.category)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnailView: some View {
        CachedThumbnailView(
            url: item.previewImageURL,
            fallbackURL: item.fallbackThumbnailURL,
            localPath: item.localThumbnailPath
        )
    }
}

private struct BadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.85))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}

private struct DetailInspectorView: View {
    let item: WallpaperItem
    let downloadProgress: Double?
    let isWorking: Bool
    let onApplyDesktop: () -> Void
    let onApplyLockScreen: () -> Void
    let onApplyBoth: () -> Void
    let isSavedLocally: Bool
    @Binding var useContinuousOverlay: Bool
    let onSaveToLocal: (() -> Void)?
    let onDeleteCustom: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let videoURL = item.effectiveVideoURL {
                    LoopingVideoPlayerView(
                        url: videoURL,
                        fallbackURLs: item.fallbackVideoURLs ?? [],
                        thumbnailURL: item.previewImageURL,
                        fallbackThumbnailURL: item.fallbackThumbnailURL,
                        localThumbnailPath: item.localThumbnailPath
                    )
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.title2.bold())
                    Text(item.category)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let progress = downloadProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                        Text("Downloading… \(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 10) {
                    Button(action: onApplyBoth) {
                        Label("Apply to Desktop & Lock Screen", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isWorking)

                    HStack(spacing: 10) {
                        Button(action: onApplyDesktop) {
                            Label("Desktop Only", systemImage: "desktopcomputer")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isWorking)

                        Button(action: onApplyLockScreen) {
                            Label("Lock Screen Only", systemImage: "lock.desktopcomputer")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isWorking)
                    }
                }

                Toggle(isOn: $useContinuousOverlay) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Continuous Desktop Loop (NSWindow)")
                            .font(.caption)
                        Text("Off = Official macOS WallpaperAgent only. On = Loops continuously while unlocked.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if let onSaveToLocal {
                    Button(action: onSaveToLocal) {
                        Label(
                            isSavedLocally ? "Saved in My Live Wallpapers" : "Add to My Live Wallpapers",
                            systemImage: isSavedLocally ? "checkmark.circle.fill" : "square.and.arrow.down"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking || isSavedLocally)
                }

                if let onDeleteCustom {
                    Divider()
                    Button(role: .destructive, action: onDeleteCustom) {
                        Label("Delete Custom Wallpaper", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 320)
    }

    private var subtitleText: String {
        if item.isCustom {
            return "Custom Local Video (.mov)"
        }
        if item.isDownloadedLocally {
            return "Cached Locally"
        }
        switch item.source {
        case .externalFeed:
            return "\(item.feedName ?? "External Feed") (Streams / Downloads on Apply)"
        case .appleAerial:
            return "4K Apple Aerial (Streams / Downloads on Apply)"
        case .custom:
            return "Custom Local Video (.mov)"
        }
    }
}
