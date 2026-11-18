import SwiftUI

struct FeedManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var feedStore: FeedStore
    let onFeedsChanged: () -> Void

    @State private var name: String = ""
    @State private var url: String = ""
    @State private var format: FeedFormat = .jsonAPI
    @State private var itemsKey: String = ""
    @State private var nextCursorKey: String = ""
    @State private var regexPattern: String = ""
    @State private var videoTemplate: String = ""
    @State private var fallbackVideoTemplates: String = ""
    @State private var previewTemplate: String = ""

    @State private var importJSONText: String = ""
    @State private var showImportJSON: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("External Wallpaper Feeds")
                        .font(.title2.bold())
                    Text("Configure JSON APIs, manifests, or web pattern feeds to browse and download live wallpapers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import JSON…") {
                    showImportJSON.toggle()
                }
                Button("Done") {
                    onFeedsChanged()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            if showImportJSON {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste Feed Config JSON (object or array):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $importJSONText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 80)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
                    HStack {
                        Spacer()
                        Button("Import") {
                            do {
                                _ = try feedStore.importConfigJSON(importJSONText)
                                importJSONText = ""
                                showImportJSON = false
                                errorMessage = nil
                                onFeedsChanged()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                        .disabled(importJSONText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }

            if feedStore.feeds.isEmpty {
                Text("No external feeds configured yet. Add one below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                List {
                    ForEach(feedStore.feeds) { feed in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { feed.isEnabled },
                                set: { enabled in
                                    var updated = feed
                                    updated.isEnabled = enabled
                                    feedStore.update(updated)
                                    onFeedsChanged()
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(feed.name)
                                    .font(.headline)
                                Text("\(feed.format.displayName) • \(feed.url)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                feedStore.delete(feed)
                                onFeedsChanged()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            Text("Add New Feed")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Name").font(.caption).foregroundStyle(.secondary)
                    TextField("e.g. My Live Feed", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("URL").font(.caption).foregroundStyle(.secondary)
                    TextField("https://example.com/wallpapers.json", text: $url)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Format").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $format) {
                        ForEach(FeedFormat.allCases) { f in
                            Text(f.displayName).tag(f)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                if format == .jsonAPI {
                    GridRow {
                        Text("Items Key").font(.caption).foregroundStyle(.secondary)
                        TextField("Optional (auto-detects wallpapers/items/data/results)", text: $itemsKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Cursor Key").font(.caption).foregroundStyle(.secondary)
                        TextField("Optional (auto-detects nextCursor/next_cursor)", text: $nextCursorKey)
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    GridRow {
                        Text("Regex").font(.caption).foregroundStyle(.secondary)
                        TextField("Capture groups: (category), (slug), (id) or (id)", text: $regexPattern)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Video URL").font(.caption).foregroundStyle(.secondary)
                        TextField("https://cdn.example.com/{id}.mp4", text: $videoTemplate)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Fallbacks").font(.caption).foregroundStyle(.secondary)
                        TextField("Optional comma-separated fallback templates", text: $fallbackVideoTemplates)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Preview URL").font(.caption).foregroundStyle(.secondary)
                        TextField("Optional https://cdn.example.com/{id}.png", text: $previewTemplate)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Add Feed") {
                    addFeed()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620)
    }

    private func addFeed() {
        let fallbacks = fallbackVideoTemplates
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let config = WallpaperFeedConfig(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            format: format,
            isEnabled: true,
            itemsKey: itemsKey.isEmpty ? nil : itemsKey,
            nextCursorKey: nextCursorKey.isEmpty ? nil : nextCursorKey,
            regexPattern: regexPattern.isEmpty ? nil : regexPattern,
            videoURLTemplate: videoTemplate.isEmpty ? nil : videoTemplate,
            fallbackVideoTemplates: fallbacks.isEmpty ? nil : fallbacks,
            previewURLTemplate: previewTemplate.isEmpty ? nil : previewTemplate
        )
        feedStore.add(config)
        name = ""
        url = ""
        itemsKey = ""
        nextCursorKey = ""
        regexPattern = ""
        videoTemplate = ""
        fallbackVideoTemplates = ""
        previewTemplate = ""
        errorMessage = nil
        onFeedsChanged()
    }
}
