import SwiftUI
import UniformTypeIdentifiers

struct CreateWallpaperSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var localStore: LocalLibraryStore
    let onCreated: (WallpaperItem, Bool, Bool) -> Void

    @State private var selectedURL: URL?
    @State private var title: String = ""
    @State private var applyDesktop: Bool = true
    @State private var applyLockScreen: Bool = true
    @State private var isImporting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Create Live Wallpaper")
                    .font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            if let url = selectedURL {
                LoopingVideoPlayerView(url: url)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
            } else {
                Button {
                    pickFile()
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("Drop a .mov or .mp4 file here, or click to browse")
                            .font(.headline)
                        Text("Videos are converted/copied to .mov with a generated thumbnail")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                            .foregroundStyle(.secondary.opacity(0.5))
                    )
                }
                .buttonStyle(.plain)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }
            }

            HStack {
                TextField("Wallpaper Name", text: $title)
                    .textFieldStyle(.roundedBorder)
                if selectedURL != nil {
                    Button("Choose Another…") {
                        pickFile()
                    }
                }
            }

            HStack(spacing: 20) {
                Toggle("Apply to Desktop", isOn: $applyDesktop)
                Toggle("Apply to Lock Screen", isOn: $applyLockScreen)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Save Live Wallpaper") {
                    Task { await importAndSave() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedURL == nil || isImporting)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.quickTimeMovie, .mpeg4Movie, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            selectedURL = url
            if title.isEmpty {
                title = url.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            let ext = url.pathExtension.lowercased()
            guard ["mov", "mp4", "m4v"].contains(ext) else { return }
            Task { @MainActor in
                self.selectedURL = url
                if self.title.isEmpty {
                    self.title = url.deletingPathExtension().lastPathComponent
                }
            }
        }
        return true
    }

    private func importAndSave() async {
        guard let url = selectedURL else { return }
        isImporting = true
        errorMessage = nil
        do {
            let item = try await localStore.importVideo(from: url, title: title)
            onCreated(item, applyDesktop, applyLockScreen)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isImporting = false
    }
}
