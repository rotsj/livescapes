import AppKit
import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum SolarHEICBuilder {
    struct PhaseFrame {
        let phase: SolarPhase
        let videoURL: URL
        let altitude: Double
        let azimuth: Double
    }

    static func buildAndApplyDynamicHEIC(
        morning: URL,
        day: URL,
        evening: URL,
        night: URL,
        outputName: String = "LiveScapes-Solar"
    ) async throws -> URL {
        let phases: [PhaseFrame] = [
            PhaseFrame(phase: .morning, videoURL: morning, altitude: 8.0, azimuth: 95.0),
            PhaseFrame(phase: .day, videoURL: day, altitude: 50.0, azimuth: 180.0),
            PhaseFrame(phase: .evening, videoURL: evening, altitude: 6.0, azimuth: 265.0),
            PhaseFrame(phase: .night, videoURL: night, altitude: -25.0, azimuth: 0.0)
        ]

        var images: [CGImage] = []
        for entry in phases {
            let img = try await extractFrame(from: entry.videoURL)
            images.append(img)
        }

        let outputURL = AppPaths.appSupportDirectory.appendingPathComponent("\(outputName).heic")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.heic.identifier as CFString,
            images.count,
            nil
        ) else {
            throw NSError(domain: "LiveScapes", code: 40, userInfo: [NSLocalizedDescriptionKey: "Could not create HEIC image destination."])
        }

        let solarInfo: [[String: Any]] = phases.enumerated().map { idx, entry in
            [
                "a": entry.altitude,
                "z": entry.azimuth,
                "i": idx
            ]
        }

        let plistDict: [String: Any] = [
            "si": solarInfo,
            "ap": [
                "l": 1,
                "d": 3
            ]
        ]

        let plistData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .binary, options: 0)
        let base64Solar = plistData.base64EncodedString()

        let metadata = CGImageMetadataCreateMutable()
        var err: Unmanaged<CFError>?
        let registered = CGImageMetadataRegisterNamespaceForPrefix(
            metadata,
            "http://ns.apple.com/namespace/1.0/" as CFString,
            "apple_desktop" as CFString,
            &err
        )
        guard registered else {
            throw NSError(domain: "LiveScapes", code: 41, userInfo: [NSLocalizedDescriptionKey: "Failed to register apple_desktop XMP namespace."])
        }

        CGImageMetadataSetValueWithPath(
            metadata,
            nil,
            "apple_desktop:solar" as CFString,
            base64Solar as CFString
        )

        for (index, cgImage) in images.enumerated() {
            if index == 0 {
                CGImageDestinationAddImageAndMetadata(destination, cgImage, metadata, nil)
            } else {
                CGImageDestinationAddImage(destination, cgImage, nil)
            }
        }

        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "LiveScapes", code: 42, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize Dynamic HEIC file."])
        }

        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(outputURL, for: screen, options: [:])
        }

        return outputURL
    }

    private static func extractFrame(from videoURL: URL) async throws -> CGImage {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        do {
            return try await generator.image(at: time).image
        } catch {
            return try await generator.image(at: .zero).image
        }
    }
}
