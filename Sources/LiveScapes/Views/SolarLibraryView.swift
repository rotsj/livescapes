import SwiftUI

struct SolarLibraryView: View {
    @ObservedObject var solarManager: SolarCollectionManager
    @ObservedObject var localStore: LocalLibraryStore
    @Binding var selectedItem: WallpaperItem?

    @State private var isBuildingHEIC: Bool = false
    @State private var isApplyingLive: Bool = false
    @State private var message: String?

    @State private var showNewPresetAlert: Bool = false
    @State private var newPresetName: String = ""
    @State private var duplicateOnCreate: Bool = false

    @State private var showRenameAlert: Bool = false
    @State private var renamePresetText: String = ""

    private var savedWallpapers: [WallpaperItem] {
        localStore.customItems
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                genericSolarSection
                configurationsSection
                phaseGridSection
            }
            .padding(16)
        }
        .alert("New Solar Configuration", isPresented: $showNewPresetAlert) {
            TextField("e.g. Cyberpunk, Minecraft", text: $newPresetName)
            Button("Create") {
                solarManager.createPreset(name: newPresetName, duplicatingCurrent: duplicateOnCreate)
                newPresetName = ""
            }
            Button("Cancel", role: .cancel) {
                newPresetName = ""
            }
        } message: {
            Text("Save a named set of Morning, Day, Evening, and Night wallpapers.")
        }
        .alert("Rename Configuration", isPresented: $showRenameAlert) {
            TextField("Configuration Name", text: $renamePresetText)
            Button("Save") {
                solarManager.renameActivePreset(to: renamePresetText)
                renamePresetText = ""
            }
            Button("Cancel", role: .cancel) {
                renamePresetText = ""
            }
        }
    }

    private var genericSolarSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: solarManager.currentPosition.phase.systemImage)
                    .font(.title)
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Solar Phase: \(solarManager.currentPosition.phase.displayName)")
                        .font(.headline)
                    Text(String(format: "Sun Altitude: %.1f°  •  Azimuth: %.1f°",
                                solarManager.currentPosition.altitudeDegrees,
                                solarManager.currentPosition.azimuthDegrees))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Text("Latitude:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Latitude", value: $solarManager.config.latitude, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 82)
                        .onChange(of: solarManager.config.latitude) { _, _ in
                            solarManager.refreshPosition()
                        }
                    Button("Recalculate") {
                        solarManager.refreshPosition()
                    }
                    .controlSize(.small)
                }
            }

            Divider()

            HStack(spacing: 12) {
                Toggle(
                    "Auto-Rotate Live Wallpapers by Solar Position",
                    isOn: Binding(
                        get: { solarManager.config.isEnabled },
                        set: { enabled in
                            if enabled {
                                solarManager.startMonitoring()
                            } else {
                                solarManager.stopMonitoring()
                            }
                        }
                    )
                )
                .toggleStyle(.switch)
                .disabled(savedWallpapers.isEmpty && !solarManager.config.isEnabled)

                Spacer()

                Button {
                    Task { await buildHEIC() }
                } label: {
                    if isBuildingHEIC {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Static Solar .heic (Desktop)", systemImage: "photo")
                    }
                }
                .buttonStyle(.bordered)
                .help("Builds a static-frame macOS Dynamic .heic for the Desktop only (does not animate on Lock Screen).")
                .disabled(isBuildingHEIC || isApplyingLive || !hasAnyAssigned)

                Button {
                    Task { await applyLiveNow() }
                } label: {
                    if isApplyingLive {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Apply Live Now", systemImage: "sun.horizon.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .help("Installs the current solar phase's animated .mov wallpaper to both Desktop & Lock Screen.")
                .disabled(isBuildingHEIC || isApplyingLive || !hasAnyAssigned)
            }

            if let text = message ?? solarManager.statusText {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private var configurationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved Configurations")
                    .font(.headline)
                Spacer()
                Button {
                    duplicateOnCreate = false
                    newPresetName = ""
                    showNewPresetAlert = true
                } label: {
                    Label("New", systemImage: "plus")
                }
                .controlSize(.small)

                Button {
                    duplicateOnCreate = true
                    newPresetName = "\(solarManager.activePreset?.name ?? "Preset") Copy"
                    showNewPresetAlert = true
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .controlSize(.small)

                if let active = solarManager.activePreset {
                    Button {
                        renamePresetText = active.name
                        showRenameAlert = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .controlSize(.small)

                    if solarManager.config.presets.count > 1 {
                        Button(role: .destructive) {
                            solarManager.deletePreset(active.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .controlSize(.small)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(solarManager.config.presets) { preset in
                        let isActive = preset.id == solarManager.activePreset?.id
                        HStack(spacing: 6) {
                            Button {
                                solarManager.selectPreset(preset.id, applyImmediately: false)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                                    Text(preset.name)
                                        .fontWeight(isActive ? .semibold : .regular)
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                solarManager.selectPreset(preset.id, applyImmediately: true)
                            } label: {
                                Text("Apply")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.2), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Switch to “\(preset.name)” and apply its current solar phase now")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isActive ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isActive ? Color.accentColor : Color.white.opacity(0.08), lineWidth: isActive ? 1.5 : 1)
                        )
                    }
                }
            }
        }
    }

    private var phaseGridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if savedWallpapers.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("No wallpapers in My Live Wallpapers yet. Import a .mov/.mp4 or click “Add to My Live Wallpapers” on any online wallpaper first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 16)], spacing: 16) {
                ForEach(SolarPhase.allCases) { phase in
                    solarPhaseCard(for: phase)
                }
            }
        }
    }

    @ViewBuilder
    private func solarPhaseCard(for phase: SolarPhase) -> some View {
        let assigned = solarManager.item(for: phase)
        let isCurrentPhase = solarManager.currentPosition.phase == phase
        let isSelectedInInspector = assigned != nil && selectedItem?.id == assigned?.id

        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let assigned {
                        CachedThumbnailView(
                            url: assigned.previewImageURL,
                            fallbackURL: nil,
                            localPath: assigned.localThumbnailPath
                        )
                    } else {
                        ZStack {
                            Color.secondary.opacity(0.15)
                            VStack(spacing: 6) {
                                Image(systemName: phase.systemImage)
                                    .font(.system(size: 28))
                                    .foregroundStyle(.secondary)
                                Text("No Wallpaper Assigned")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture {
                    if let assigned {
                        selectedItem = assigned
                    }
                }

                HStack {
                    Label(phase.displayName, systemImage: phase.systemImage)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())

                    Spacer()

                    if isCurrentPhase {
                        Text("Active Phase")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.yellow.opacity(0.85), in: Capsule())
                            .foregroundStyle(.black)
                    }
                }
                .padding(8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelectedInInspector ? Color.accentColor :
                            (isCurrentPhase ? Color.yellow.opacity(0.6) : Color.white.opacity(0.08)),
                        lineWidth: isSelectedInInspector ? 2.5 : 1
                    )
            )

            if let assigned {
                Text(assigned.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(assigned.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Unassigned")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Select from My Live Wallpapers below")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Picker("", selection: Binding(
                    get: { assigned?.id ?? "" },
                    set: { newID in
                        let found = savedWallpapers.first { $0.id == newID }
                        solarManager.setItem(found, for: phase)
                        if let found {
                            selectedItem = found
                        }
                    }
                )) {
                    Text("— None —").tag("")
                    ForEach(pickerCandidates(including: assigned)) { item in
                        Text("\(item.title) (\(item.category))").tag(item.id)
                    }
                }
                .labelsHidden()
                .disabled(savedWallpapers.isEmpty)

                if let selected = selectedItem, selected.isCustom, selected.id != assigned?.id {
                    Button("Use Selected") {
                        solarManager.setItem(selected, for: phase)
                    }
                    .controlSize(.small)
                    .help("Assign “\(selected.title)” to \(phase.displayName)")
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
    }

    private var hasAnyAssigned: Bool {
        SolarPhase.allCases.contains { solarManager.item(for: $0) != nil }
    }

    private func pickerCandidates(including current: WallpaperItem?) -> [WallpaperItem] {
        var list = savedWallpapers
        if let current, current.isCustom, !list.contains(where: { $0.id == current.id }) {
            list.insert(current, at: 0)
        }
        return list
    }

    private func applyLiveNow() async {
        isApplyingLive = true
        defer { isApplyingLive = false }
        message = nil
        await solarManager.applyNow()
    }

    private func buildHEIC() async {
        isBuildingHEIC = true
        defer { isBuildingHEIC = false }
        do {
            let url = try await solarManager.buildAndApplyDynamicHEIC()
            message = "Static Solar .heic created and applied to Desktop: \(url.path)"
        } catch {
            message = "Failed to build Static Solar .heic: \(error.localizedDescription)"
        }
    }
}

