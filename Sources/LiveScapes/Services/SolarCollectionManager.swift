import AppKit
import Foundation

struct SolarPreset: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var morningItem: WallpaperItem?
    var dayItem: WallpaperItem?
    var eveningItem: WallpaperItem?
    var nightItem: WallpaperItem?

    func item(for phase: SolarPhase) -> WallpaperItem? {
        switch phase {
        case .morning: return morningItem
        case .day: return dayItem
        case .evening: return eveningItem
        case .night: return nightItem
        }
    }

    mutating func setItem(_ item: WallpaperItem?, for phase: SolarPhase) {
        switch phase {
        case .morning: morningItem = item
        case .day: dayItem = item
        case .evening: eveningItem = item
        case .night: nightItem = item
        }
    }
}

struct SolarCollectionConfig: Codable {
    var isEnabled: Bool = false
    var morningItem: WallpaperItem?
    var dayItem: WallpaperItem?
    var eveningItem: WallpaperItem?
    var nightItem: WallpaperItem?
    var presets: [SolarPreset] = []
    var activePresetID: UUID?
    var latitude: Double = 37.7749
    var useCustomLongitude: Bool = false
    var customLongitude: Double = 0.0
    var lastAppliedPhase: SolarPhase?
}

@MainActor
final class SolarCollectionManager: ObservableObject {
    @Published var config: SolarCollectionConfig = SolarCollectionConfig() {
        didSet { save() }
    }
    @Published private(set) var currentPosition: SolarPosition = SolarCalculator.position()
    @Published private(set) var statusText: String?
    @Published var activeGallerySelection: WallpaperItem?

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?
    private weak var downloader: VideoDownloader?
    private weak var desktopManager: DesktopWallpaperManager?
    private var useContinuousOverlay: Bool = false

    private static var configURL: URL {
        AppPaths.appSupportDirectory.appendingPathComponent("solar_collection.json")
    }

    init() {
        load()
        ensureDefaultPreset()
        refreshPosition()
    }

    func configure(downloader: VideoDownloader, desktopManager: DesktopWallpaperManager) {
        self.downloader = downloader
        self.desktopManager = desktopManager
        if config.isEnabled {
            startMonitoring()
        }
    }

    func setContinuousOverlay(_ enabled: Bool) {
        self.useContinuousOverlay = enabled
    }

    var activePreset: SolarPreset? {
        if let activeID = config.activePresetID,
           let match = config.presets.first(where: { $0.id == activeID }) {
            return match
        }
        return config.presets.first
    }

    func item(for phase: SolarPhase) -> WallpaperItem? {
        if let preset = activePreset {
            return preset.item(for: phase)
        }
        switch phase {
        case .morning: return config.morningItem
        case .day: return config.dayItem
        case .evening: return config.eveningItem
        case .night: return config.nightItem
        }
    }

    func setItem(_ item: WallpaperItem?, for phase: SolarPhase) {
        ensureDefaultPreset()
        if let activeID = config.activePresetID,
           let idx = config.presets.firstIndex(where: { $0.id == activeID }) {
            config.presets[idx].setItem(item, for: phase)
            syncLegacySlots(from: config.presets[idx])
        }
        if config.isEnabled {
            Task {
                await evaluateAndApplyIfNeeded(force: true)
            }
        }
    }

    func selectPreset(_ id: UUID, applyImmediately: Bool = false) {
        guard let preset = config.presets.first(where: { $0.id == id }) else { return }
        config.activePresetID = id
        syncLegacySlots(from: preset)
        if applyImmediately {
            Task { await applyNow() }
        } else if config.isEnabled {
            Task { await evaluateAndApplyIfNeeded(force: true) }
        }
    }

    @discardableResult
    func createPreset(name: String, duplicatingCurrent: Bool = false) -> SolarPreset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Preset \(config.presets.count + 1)" : trimmed
        let current = activePreset
        let preset = SolarPreset(
            id: UUID(),
            name: finalName,
            morningItem: duplicatingCurrent ? current?.morningItem : nil,
            dayItem: duplicatingCurrent ? current?.dayItem : nil,
            eveningItem: duplicatingCurrent ? current?.eveningItem : nil,
            nightItem: duplicatingCurrent ? current?.nightItem : nil
        )
        config.presets.append(preset)
        config.activePresetID = preset.id
        syncLegacySlots(from: preset)
        return preset
    }

    func renameActivePreset(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let activeID = config.activePresetID,
              let idx = config.presets.firstIndex(where: { $0.id == activeID }) else { return }
        config.presets[idx].name = trimmed
    }

    func deletePreset(_ id: UUID) {
        guard config.presets.count > 1 else { return }
        config.presets.removeAll { $0.id == id }
        if config.activePresetID == id, let first = config.presets.first {
            config.activePresetID = first.id
            syncLegacySlots(from: first)
            if config.isEnabled {
                Task { await evaluateAndApplyIfNeeded(force: true) }
            }
        }
    }

    private func ensureDefaultPreset() {
        if config.presets.isEmpty {
            let initial = SolarPreset(
                id: UUID(),
                name: "Default",
                morningItem: config.morningItem,
                dayItem: config.dayItem,
                eveningItem: config.eveningItem,
                nightItem: config.nightItem
            )
            config.presets = [initial]
            config.activePresetID = initial.id
        } else if config.activePresetID == nil || !config.presets.contains(where: { $0.id == config.activePresetID }) {
            config.activePresetID = config.presets.first?.id
        }
    }

    private func syncLegacySlots(from preset: SolarPreset) {
        config.morningItem = preset.morningItem
        config.dayItem = preset.dayItem
        config.eveningItem = preset.eveningItem
        config.nightItem = preset.nightItem
    }

    func refreshPosition() {
        currentPosition = SolarCalculator.position(
            date: Date(),
            latitude: config.latitude,
            longitude: config.useCustomLongitude ? config.customLongitude : nil
        )
    }

    func startMonitoring() {
        stopMonitoring()
        config.isEnabled = true

        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.evaluateAndApplyIfNeeded(force: false)
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.evaluateAndApplyIfNeeded(force: false)
            }
        }

        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.evaluateAndApplyIfNeeded(force: false)
            }
        }

        Task {
            await evaluateAndApplyIfNeeded(force: true)
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let unlockObserver {
            DistributedNotificationCenter.default().removeObserver(unlockObserver)
            self.unlockObserver = nil
        }
        config.isEnabled = false
    }

    func applyNow() async {
        refreshPosition()
        await applyCurrentPhase()
    }

    func evaluateAndApplyIfNeeded(force: Bool) async {
        refreshPosition()
        guard config.isEnabled else { return }

        let phase = currentPosition.phase
        if !force && config.lastAppliedPhase == phase {
            return
        }

        await applyCurrentPhase()
    }

    private func applyCurrentPhase() async {
        let phase = currentPosition.phase
        guard let targetItem = resolvedItem(for: phase),
              let downloader else {
            statusText = "No wallpaper assigned for \(phase.displayName)."
            return
        }

        do {
            statusText = "Solar Auto-Adjust: applying \(targetItem.title) (\(phase.displayName))…"
            let localURL = try await downloader.ensureLocalVideo(for: targetItem)
            try await LockScreenInstaller.install(item: targetItem, localVideoURL: localURL, target: .both)
            if useContinuousOverlay {
                desktopManager?.apply(videoURL: localURL, title: targetItem.title)
            }
            config.lastAppliedPhase = phase
            statusText = "Solar Auto-Adjust: active \(targetItem.title) (\(phase.displayName), sun \(String(format: "%.1f°", currentPosition.altitudeDegrees)))."
        } catch {
            statusText = "Solar Auto-Adjust error: \(error.localizedDescription)"
        }
    }

    func buildAndApplyDynamicHEIC() async throws -> URL {
        guard let downloader else {
            throw NSError(domain: "LiveScapes", code: 50, userInfo: [NSLocalizedDescriptionKey: "Downloader not ready."])
        }
        guard let m = item(for: .morning) ?? resolvedFallbackItem(),
              let d = item(for: .day) ?? resolvedFallbackItem(),
              let e = item(for: .evening) ?? resolvedFallbackItem(),
              let n = item(for: .night) ?? resolvedFallbackItem() else {
            throw NSError(domain: "LiveScapes", code: 51, userInfo: [NSLocalizedDescriptionKey: "Assign at least one wallpaper first."])
        }

        statusText = "Downloading & building Dynamic Solar .heic…"
        let mURL = try await downloader.ensureLocalVideo(for: m)
        let dURL = try await downloader.ensureLocalVideo(for: d)
        let eURL = try await downloader.ensureLocalVideo(for: e)
        let nURL = try await downloader.ensureLocalVideo(for: n)

        let heicURL = try await SolarHEICBuilder.buildAndApplyDynamicHEIC(
            morning: mURL,
            day: dURL,
            evening: eURL,
            night: nURL
        )
        desktopManager?.stop()
        statusText = "Applied official Dynamic Solar .heic (\(heicURL.lastPathComponent))."
        return heicURL
    }

    private func resolvedItem(for phase: SolarPhase) -> WallpaperItem? {
        if let exact = item(for: phase) { return exact }
        return resolvedFallbackItem()
    }

    private func resolvedFallbackItem() -> WallpaperItem? {
        item(for: .day) ?? item(for: .morning) ?? item(for: .evening) ?? item(for: .night)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: Self.configURL.path),
              let data = try? Data(contentsOf: Self.configURL),
              let decoded = try? JSONDecoder().decode(SolarCollectionConfig.self, from: data) else {
            return
        }
        config = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: Self.configURL, options: .atomic)
    }
}
