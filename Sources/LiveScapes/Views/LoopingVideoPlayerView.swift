import AVFoundation
import SwiftUI

struct LoopingVideoPlayerView: View {
    let url: URL
    var fallbackURLs: [URL] = []
    var thumbnailURL: URL? = nil
    var fallbackThumbnailURL: URL? = nil
    var localThumbnailPath: String? = nil

    @State private var isReady: Bool = false
    @State private var errorText: String? = nil

    var body: some View {
        ZStack {
            if thumbnailURL != nil || localThumbnailPath != nil {
                CachedThumbnailView(
                    url: thumbnailURL,
                    fallbackURL: fallbackThumbnailURL,
                    localPath: localThumbnailPath
                )
            }

            VideoPlayerRepresentable(
                url: url,
                fallbackURLs: fallbackURLs,
                isReady: $isReady,
                errorText: $errorText
            )

            if !isReady && errorText == nil {
                ProgressView()
                    .controlSize(.regular)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }

            if let errorText {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3)
                    Text(errorText)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .onChange(of: url) { _, _ in
            isReady = false
            errorText = nil
        }
    }
}

private struct VideoPlayerRepresentable: NSViewRepresentable {
    let url: URL
    let fallbackURLs: [URL]
    @Binding var isReady: Bool
    @Binding var errorText: String?

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.onReady = {
            DispatchQueue.main.async { self.isReady = true }
        }
        view.onError = { message in
            DispatchQueue.main.async { self.errorText = message }
        }
        view.update(url: url, fallbackURLs: fallbackURLs)
        return view
    }

    func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        nsView.onReady = {
            DispatchQueue.main.async { self.isReady = true }
        }
        nsView.onError = { message in
            DispatchQueue.main.async { self.errorText = message }
        }
        nsView.update(url: url, fallbackURLs: fallbackURLs)
    }
}

final class PlayerContainerView: NSView {
    var onReady: (() -> Void)?
    var onError: ((String) -> Void)?

    private var player: AVPlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var currentURL: URL?
    private var fallbackURLs: [URL] = []
    private var nextFallbackIndex: Int = 0

    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = bounds
        CATransaction.commit()
    }

    func update(url: URL, fallbackURLs: [URL]) {
        guard url != currentURL else { return }
        self.currentURL = url
        self.fallbackURLs = fallbackURLs
        self.nextFallbackIndex = 0
        loadPlayer(with: url)
    }

    private func loadPlayer(with url: URL) {
        cleanupPlayer()

        let assetOptions: [String: Any] = url.isFileURL ? [:] : [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": AppNetwork.browserUserAgent
            ]
        ]
        let asset = AVURLAsset(url: url, options: assetOptions)
        let templateItem = AVPlayerItem(asset: asset)

        let activePlayer: AVPlayer
        let observedItem: AVPlayerItem

        if url.isFileURL {
            let queuePlayer = AVQueuePlayer()
            queuePlayer.isMuted = true
            self.looper = AVPlayerLooper(player: queuePlayer, templateItem: templateItem)
            activePlayer = queuePlayer
            observedItem = queuePlayer.currentItem ?? templateItem
        } else {
            let streamPlayer = AVPlayer(playerItem: templateItem)
            streamPlayer.isMuted = true
            streamPlayer.automaticallyWaitsToMinimizeStalling = true
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: templateItem,
                queue: .main
            ) { [weak streamPlayer] _ in
                streamPlayer?.seek(to: .zero)
                streamPlayer?.play()
            }
            activePlayer = streamPlayer
            observedItem = templateItem
        }

        timeControlObserver = activePlayer.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] p, _ in
            if p.timeControlStatus == .playing {
                self?.onReady?()
            }
        }

        statusObserver = observedItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            guard let self else { return }
            switch item.status {
            case .readyToPlay:
                self.onReady?()
            case .failed:
                if self.nextFallbackIndex < self.fallbackURLs.count {
                    let fb = self.fallbackURLs[self.nextFallbackIndex]
                    self.nextFallbackIndex += 1
                    DispatchQueue.main.async {
                        self.loadPlayer(with: fb)
                    }
                } else {
                    let msg = item.error?.localizedDescription ?? "Failed to load video."
                    self.onError?(msg)
                }
            case .unknown:
                break
            @unknown default:
                break
            }
        }

        let layer = AVPlayerLayer(player: activePlayer)
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = NSColor.clear.cgColor
        self.layer?.addSublayer(layer)

        self.player = activePlayer
        self.playerLayer = layer

        activePlayer.play()
    }

    private func cleanupPlayer() {
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        looper = nil
        player = nil
    }

    deinit {
        cleanupPlayer()
    }
}
