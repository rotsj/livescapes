import Foundation

@MainActor
final class VideoDownloader: NSObject, ObservableObject {
    @Published var activeDownloads: [String: Double] = [:]

    func ensureLocalVideo(for item: WallpaperItem) async throws -> URL {
        if let localPath = item.localVideoPath, FileManager.default.fileExists(atPath: localPath) {
            return URL(fileURLWithPath: localPath)
        }

        let cacheMOV = AppPaths.cacheDirectory.appendingPathComponent("\(item.id).mov")
        if FileManager.default.fileExists(atPath: cacheMOV.path) {
            return cacheMOV
        }

        guard let remoteURL = item.remoteVideoURL else {
            throw NSError(domain: "LiveScapes", code: 10, userInfo: [NSLocalizedDescriptionKey: "No video URL available for \(item.title)."])
        }

        let ext = remoteURL.pathExtension.isEmpty ? "mov" : remoteURL.pathExtension.lowercased()
        let cacheURL = AppPaths.cacheDirectory.appendingPathComponent("\(item.id).\(ext)")
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }

        activeDownloads[item.id] = 0.01
        defer { activeDownloads.removeValue(forKey: item.id) }

        let delegate = DownloadProgressDelegate { [weak self] progress in
            Task { @MainActor in
                self?.activeDownloads[item.id] = progress
            }
        }

        var candidates = [remoteURL]
        for extra in item.fallbackVideoURLs ?? [] where !candidates.contains(extra) {
            candidates.append(extra)
        }

        var lastTempURL: URL?
        var lastResponse: URLResponse?
        for candidate in candidates {
            let (t, r) = try await AppNetwork.session.download(from: candidate, delegate: delegate)
            lastTempURL = t
            lastResponse = r
            if let http = r as? HTTPURLResponse, http.statusCode == 404 {
                try? FileManager.default.removeItem(at: t)
                continue
            }
            break
        }

        guard let tempURL = lastTempURL, let response = lastResponse else {
            throw NSError(domain: "LiveScapes", code: 11, userInfo: [NSLocalizedDescriptionKey: "Download failed."])
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "LiveScapes", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Download failed with HTTP \(http.statusCode)."])
        }

        if FileManager.default.fileExists(atPath: cacheURL.path) {
            try FileManager.default.removeItem(at: cacheURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: cacheURL)
        return cacheURL
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
}
