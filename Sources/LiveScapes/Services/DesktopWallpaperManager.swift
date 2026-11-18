import AppKit
import AVFoundation
import Foundation

@MainActor
final class DesktopWallpaperManager: ObservableObject {
    @Published private(set) var currentVideoURL: URL?
    @Published private(set) var currentTitle: String?
    @Published private(set) var isPlaying: Bool = false

    private var windows: [NSWindow] = []
    private var loopers: [AVPlayerLooper] = []
    private var players: [AVQueuePlayer] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        let screenObs = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildWindowsIfNeeded()
            }
        }
        observers.append(screenObs)

        let sleepObs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
        }
        observers.append(sleepObs)

        let wakeObs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resume()
            }
        }
        observers.append(wakeObs)
    }

    deinit {
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    func apply(videoURL: URL, title: String) {
        currentVideoURL = videoURL
        currentTitle = title
        rebuildWindows(with: videoURL)
        isPlaying = true
    }

    func pause() {
        players.forEach { $0.pause() }
        isPlaying = false
    }

    func resume() {
        guard currentVideoURL != nil else { return }
        players.forEach { $0.play() }
        isPlaying = true
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func stop() {
        for win in windows {
            win.orderOut(nil)
            win.close()
        }
        windows.removeAll()
        loopers.removeAll()
        players.forEach { $0.pause() }
        players.removeAll()
        currentVideoURL = nil
        currentTitle = nil
        isPlaying = false
    }

    private func rebuildWindowsIfNeeded() {
        guard let url = currentVideoURL else { return }
        let wasPlaying = isPlaying
        rebuildWindows(with: url)
        if !wasPlaying {
            pause()
        }
    }

    private func rebuildWindows(with url: URL) {
        for win in windows {
            win.orderOut(nil)
            win.close()
        }
        windows.removeAll()
        loopers.removeAll()
        players.forEach { $0.pause() }
        players.removeAll()

        let desktopLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) - 1

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = NSWindow.Level(rawValue: desktopLevel)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            window.ignoresMouseEvents = true
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.isReleasedWhenClosed = false

            let hostView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            hostView.wantsLayer = true

            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            let looper = AVPlayerLooper(player: player, templateItem: item)

            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.frame = hostView.bounds
            playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            playerLayer.videoGravity = .resizeAspectFill

            hostView.layer?.addSublayer(playerLayer)
            window.contentView = hostView
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()

            player.play()

            windows.append(window)
            players.append(player)
            loopers.append(looper)
        }
    }
}
