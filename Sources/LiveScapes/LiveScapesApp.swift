import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct LiveScapesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var desktopManager = DesktopWallpaperManager()
    @StateObject private var localStore = LocalLibraryStore()
    @StateObject private var downloader = VideoDownloader()
    @StateObject private var solarManager = SolarCollectionManager()
    @StateObject private var feedStore = FeedStore()

    var body: some Scene {
        WindowGroup("LiveScapes", id: "main") {
            ContentView(
                desktopManager: desktopManager,
                localStore: localStore,
                downloader: downloader,
                solarManager: solarManager,
                feedStore: feedStore
            )
            .frame(minWidth: 960, minHeight: 620)
            .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1120, height: 700)

        MenuBarExtra("LiveScapes", systemImage: "sparkles.tv") {
            if let title = desktopManager.currentTitle {
                Text("Playing: \(title)")
                Button(desktopManager.isPlaying ? "Pause Desktop Wallpaper" : "Resume Desktop Wallpaper") {
                    desktopManager.togglePlayPause()
                }
                Button("Stop Desktop Wallpaper") {
                    desktopManager.stop()
                }
                Divider()
            } else {
                Text("No Desktop Wallpaper Active")
                Divider()
            }

            Button("Open LiveScapes") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title == "LiveScapes" }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }

            Divider()
            Button("Quit LiveScapes") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
