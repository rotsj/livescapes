# LiveScapes

A native macOS live wallpaper manager (macOS 14.0+) built with SwiftUI, AppKit, and AVFoundation. Preview and apply animated video wallpapers to both your **Desktop** and **Lock Screen**, configure external wallpaper feeds, and automate time-of-day transitions with **Solar Auto-Adjust**.

---

## Features

- **Official Desktop & Lock Screen Live Wallpapers**: Registers and applies `.mov` / `.mp4` videos through macOS `WallpaperAgent` (`com.apple.wallpaper`) so they animate natively on both your Desktop and Lock Screen. Short clips (< 120s) are automatically extended so Lock Screen playback loops smoothly.
- **Continuous Desktop Loop (Optional)**: Toggle an `NSWindow` + `AVPlayerLooper` overlay to continuously loop videos on the Desktop while unlocked.
- **My Live Wallpapers**: Import local `.mov` or `.mp4` files (or save wallpapers from feeds locally) with automatic `.mov` conversion and thumbnail generation.
- **Apple 4K Aerials**: Browse and apply macOS's built-in 4K Aerials catalog grouped by category.
- **Configurable External Feeds**: Add one or more custom JSON API / manifest feeds or web pattern feeds without any hardcoded third-party services. Supports cursor pagination, automatic loading, and JSON config import.
- **Solar Auto-Adjust (`Library → Solar`)**: Calculates real-time solar altitude and azimuth (`Morning`, `Day`, `Evening`, `Night`) and rotates your live Desktop & Lock Screen wallpapers automatically. Save and switch between multiple named configurations (e.g. *Cyberpunk*, *Minecraft*), or build a static-frame solar `.heic` for the Desktop.
- **Menu Bar Extra**: Quick pause/resume/stop controls and window access from the menu bar.

---

## Installation

### Download from GitHub Releases
1. Download **`LiveScapes-macOS-universal.dmg`** or **`LiveScapes-macOS-universal.zip`** from the [Releases](../../releases) page (Universal Binary for Apple Silicon & Intel Macs).
2. Move **`LiveScapes.app`** into **`/Applications`**.
3. **Gatekeeper**: Because release builds are ad-hoc signed (not notarized with an Apple Developer ID), macOS Gatekeeper will block the first launch. Allow it using either method:
   - **Terminal (fastest):**
     ```bash
     xattr -cr /Applications/LiveScapes.app
     ```
   - **System Settings:** Attempt to open `LiveScapes.app`, click **Done** on the prompt, then open **System Settings → Privacy & Security** and click **Open Anyway**.

---

## Usage

### Importing & Applying Wallpapers
1. Click **+** (**Create Live Wallpaper**) in the toolbar, drop a `.mov` or `.mp4` file, give it a name, and save it to **My Live Wallpapers**.
2. Select any wallpaper to preview it live in the right-hand inspector, then click **Apply to Desktop & Lock Screen** (or **Desktop Only** / **Lock Screen Only**).

### Configuring External Feeds
1. Click **Configure Feeds** in the toolbar (or **External Feeds → Configure Feeds…** in the sidebar).
2. Add a feed using either format:
   - **JSON API / Manifest (`json`)**: Supports top-level arrays or object-wrapped lists (`wallpapers`, `items`, `data`, `results`, `entries`, `assets`, or a custom `itemsKey`) and optional cursor pagination.
   - **Web Sitemap / Pattern (`pattern`)**: Matches items from an XML/HTML URL using a `regexPattern` and expands `videoURLTemplate` / `previewURLTemplate` placeholders (`{id}`, `{id_upper}`, `{id_lower}`, `{slug}`, `{category}`).
3. You can also bulk-import feeds via **Import JSON…** (or copy a `feeds.json` file to `~/Library/Application Support/LiveScapes/feeds.json`).

### Solar Auto-Adjust
1. Open **Library → Solar** in the sidebar.
2. Assign wallpapers from **My Live Wallpapers** to **Morning**, **Day**, **Evening**, and **Night**.
3. Save multiple named configurations using **New**, **Duplicate**, **Rename**, and **Delete**, and switch/apply them with one click.
4. Enable **Auto-Rotate Live Wallpapers by Solar Position** (or click **Apply Live Now**) to install the active solar phase's animated wallpaper to both Desktop & Lock Screen.

---

## Building from Source

Requires macOS 14.0+ and Xcode / Swift 5.9+.

```bash
# Build for your current Mac's architecture
./scripts/build_app.sh

# Or build a Universal Binary (arm64 + x86_64)
./scripts/build_app.sh --universal
```

The built app bundle is output to `build/LiveScapes.app`.
