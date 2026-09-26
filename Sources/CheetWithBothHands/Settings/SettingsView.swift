import AppKit
import CheetCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding<SettingsPane?>(
                get: { navigation.pane },
                set: { if let pane = $0 { navigation.pane = pane } }
            )) {
                ForEach(SettingsPane.allCases) { pane in
                    Label(pane.title, systemImage: pane.symbol).tag(pane)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 190)

            Divider()

            Group {
                switch navigation.pane {
                case .general: GeneralPane(model: model)
                case .hotkeys: HotkeysPane(model: model)
                case .appearance: AppearancePane(model: model)
                case .layout: LayoutPane(model: model)
                case .cheets: CheetsPane(model: model, navigation: navigation)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 560)
    }
}

// MARK: - General

struct GeneralPane: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, wanted in
                        guard wanted != LoginItem.isEnabled else { return }
                        AppController.shared.toggleLaunchAtLogin()
                        launchAtLogin = LoginItem.isEnabled || LoginItem.needsApproval
                    }
                if LoginItem.needsApproval {
                    Text("Waiting for approval in System Settings › General › Login Items.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section {
                Picker("Icon style", selection: $model.settings.branding.iconScheme) {
                    ForEach(IconScheme.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Group {
                    Toggle("Show the splash screen at launch", isOn: $model.settings.branding.showSplash)
                    Toggle("Show Cheeter in the cheet picker", isOn: $model.settings.branding.showPickerMascot)
                }
                .disabled(model.settings.branding.iconScheme != .cheeter)
            } header: {
                Text("Icons")
            } footer: {
                Text("Sets the app icon in the Dock and ⌘-Tab, and the menu bar icon. The Finder icon is always Cheeter.")
            }

            Section("When a cheet hotkey is pressed") {
                Picker("Behavior", selection: $model.settings.behavior.trigger) {
                    ForEach(TriggerMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if model.settings.behavior.trigger == .smart {
                    LabeledSlider(title: "Counts as a hold after", value: $model.settings.behavior.holdThreshold, range: 0.15...1.0, format: .seconds)
                }
                LabeledSlider(title: "Fade duration", value: $model.settings.behavior.fadeDuration, range: 0...0.6, format: .seconds)
                Toggle("Focus the overlay so you can type to filter", isOn: $model.settings.behavior.takeFocus)
                Toggle("Hide when clicking outside the overlay", isOn: $model.settings.behavior.dismissOnOutsideClick)
                Toggle("Show on every Space and over full-screen apps", isOn: $model.settings.behavior.showOnAllSpaces)
            }

            Section("Interaction") {
                Toggle("Click a cell to copy it", isOn: $model.settings.behavior.copyOnClick)
                Toggle("Include images when importing web pages", isOn: $model.settings.behavior.importImages)
                Toggle("Ghost mode — overlay ignores the mouse (click-through)", isOn: $model.settings.behavior.ghostMode)
                Text("Ghost mode lets you keep a cheet up while clicking through it. Turn it off from the menu bar, or assign a Ghost Mode hotkey.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Library") {
                LabeledContent("Cheets", value: "\(model.cheets.count)")
                LabeledContent("Data folder") {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.store.libraryURL])
                    }
                }
                HStack {
                    Button("Export Library…") { AppController.shared.exportLibrary() }
                    Button("Import Library…") { AppController.shared.importLibrary() }
                    Spacer()
                    Button("Restore Sample Cheets") { model.restoreSamples() }
                }
            }

            Section {
                Button("Reset All Settings…", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Resets hotkeys, appearance, layout, behavior and icons. Your cheets are kept.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all settings to their defaults?", isPresented: $confirmReset) {
            Button("Reset Settings", role: .destructive) {
                model.settings = AppSettings()
                model.viewState.globalFrame = nil
            }
        }
    }
}

// MARK: - Hotkeys

struct HotkeysPane: View {
    @Bindable var model: AppModel

    var body: some View {
        let hotkeys = $model.settings.hotkeys
        Form {
            Section {
                Toggle("Enable global hotkeys", isOn: hotkeys.enabled)
            } footer: {
                Text("Hotkeys work from any app and don't need Accessibility permission.")
            }

            Section("Number shortcuts") {
                Toggle("Map the first ten cheets to base combo + 1…9, 0", isOn: hotkeys.autoNumbering)
                LabeledContent("Base combo") {
                    ModifierPicker(selection: hotkeys.baseModifiers)
                }
                let base = model.settings.hotkeys.baseModifiers
                if !base.hasPrimaryModifier {
                    Label("Include at least one of ⌃, ⌥ or ⌘.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Text("Cheet 1 → \(base.symbols)1   ·   Cheet 2 → \(base.symbols)2   ·   …   ·   Cheet 10 → \(base.symbols)0")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text("Tip: tap a combo to pin a cheet, or hold it to peek and let go to hide.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Opening alongside") {
                Toggle("Add ⇧ to a cheet's shortcut to open it alongside the cheets already showing", isOn: hotkeys.shiftForAlongside)
                Text("Without ⇧, a cheet's shortcut replaces the cheet in the active window. In the picker, ⇧↩ opens alongside.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Global actions") {
                LabeledContent("Cheet picker") { globalRecorder(hotkeys.picker, action: .showPicker) }
                LabeledContent("Toggle last cheet") { globalRecorder(hotkeys.toggleLast, action: .toggleLastCheet) }
                LabeledContent("Ghost mode on / off") { globalRecorder(hotkeys.ghostMode, action: .toggleGhostMode) }
                LabeledContent("Tile cheet windows") { globalRecorder(hotkeys.tile, action: .tileWindows) }
                LabeledContent("Stash cheet windows") { globalRecorder(hotkeys.stash, action: .stashWindows) }
            }

            Section("Per-cheet shortcuts") {
                if model.cheets.isEmpty {
                    Text("No cheets yet.").foregroundStyle(.secondary)
                }
                ForEach(Array(model.cheets.enumerated()), id: \.element.id) { index, cheet in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(cheet.title)
                            .lineLimit(1)
                            .frame(width: 170, alignment: .leading)
                        CheetHotkeyEditor(model: model, cheet: model.binding(forCheet: cheet.id))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func globalRecorder(_ binding: Binding<KeyCombo?>, action: HotkeyAction) -> some View {
        HStack {
            HotkeyStatusBadge(model: model, action: action, requested: binding.wrappedValue)
            HotkeyRecorder(combo: binding)
        }
    }
}

/// Automatic / Custom / None picker plus recorder and status for one cheet.
struct CheetHotkeyEditor: View {
    let model: AppModel
    @Binding var cheet: Cheet

    var body: some View {
        HStack(spacing: 8) {
            Picker("Shortcut", selection: Binding(
                get: { cheet.hotkey.mode },
                set: { mode in cheet.hotkey = HotkeyAssignment(mode: mode, combo: cheet.hotkey.combo) }
            )) {
                Text("Automatic").tag(HotkeyAssignment.Mode.automatic)
                Text("Custom").tag(HotkeyAssignment.Mode.custom)
                Text("None").tag(HotkeyAssignment.Mode.disabled)
            }
            .labelsHidden()
            .fixedSize()

            switch cheet.hotkey.mode {
            case .automatic:
                Text(automaticDescription)
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .rounded))
            case .custom:
                HotkeyRecorder(combo: Binding(
                    get: { cheet.hotkey.combo },
                    set: { cheet.hotkey = HotkeyAssignment(mode: .custom, combo: $0) }
                ))
            case .disabled:
                Text("No shortcut").foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            HotkeyStatusBadge(model: model, action: .showCheet(cheet.id), requested: cheet.hotkey.mode == .custom ? cheet.hotkey.combo : nil)
            if model.settings.hotkeys.shiftForAlongside {
                if let alongside = model.hotkeyPlan.combo(for: .showCheetAlongside(cheet.id)) {
                    Text(alongside.displayString).font(.caption).foregroundStyle(.tertiary).help("Opens alongside")
                }
                HotkeyStatusBadge(model: model, action: .showCheetAlongside(cheet.id), requested: nil)
            }
        }
    }

    private var automaticDescription: String {
        let settings = model.settings.hotkeys
        guard settings.autoNumbering else { return "Number shortcuts are off" }
        guard let index = model.index(of: cheet.id) else { return "" }
        guard let combo = HotkeyResolver.automaticCombo(forIndex: index, base: settings.baseModifiers) else {
            return settings.baseModifiers.hasPrimaryModifier ? "No number slot (position \(index + 1))" : "Base combo needs ⌃, ⌥ or ⌘"
        }
        return combo.displayString
    }
}

/// ✓ when registered, ⚠︎ when taken by another action or refused by the system.
struct HotkeyStatusBadge: View {
    let model: AppModel
    let action: HotkeyAction
    let requested: KeyCombo?

    var body: some View {
        let plan = model.hotkeyPlan
        if let wanted = plan.conflicts[action] {
            Label("Taken by \(owner(of: wanted))", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.orange)
                .help("\(wanted.displayString) is already used by \(owner(of: wanted))")
        } else if let combo = plan.combo(for: action) {
            if model.hotkeyFailures.contains(combo) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                    .help("macOS refused \(combo.displayString) — another app or a system shortcut probably owns it")
            } else if !model.settings.hotkeys.enabled {
                Image(systemName: "pause.circle").foregroundStyle(.secondary).help("Global hotkeys are turned off")
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("\(combo.displayString) is active")
            }
        }
    }

    private func owner(of combo: KeyCombo) -> String {
        guard let binding = model.hotkeyPlan.bindings.first(where: { $0.combo == combo }) else { return "another shortcut" }
        switch binding.action {
        case .showCheet(let id): return "“\(model.cheet(id: id)?.title ?? "a cheet")”"
        case .showPicker: return "the cheet picker"
        case .toggleLastCheet: return "toggle last cheet"
        case .toggleGhostMode: return "ghost mode"
        case .tileWindows: return "tile cheet windows"
        case .stashWindows: return "stash cheet windows"
        case .recallWorkspace(let id): return "workspace “\(model.workspaces.first { $0.id == id }?.name ?? "?")”"
        case .showCheetAlongside(let id): return "“\(model.cheet(id: id)?.title ?? "a cheet")” (alongside)"
        }
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                AppearancePreview(appearance: model.settings.appearance)
                    .frame(height: 230)
                    .listRowInsets(EdgeInsets())
                HStack {
                    Text("Cheets with a custom look keep their own settings (Cheets › Appearance).")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Show on Screen") { AppController.shared.overlay.toggleLast() }
                    Button("Reset") { model.settings.appearance = Appearance() }
                }
            }
            AppearanceForm(appearance: $model.settings.appearance)
        }
        .formStyle(.grouped)
    }
}

struct AppearanceForm: View {
    @Binding var appearance: Appearance

    private static let fontFamilies: [String] = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }

    var body: some View {
        Section("Background") {
            Picker("Material", selection: $appearance.material) {
                ForEach(MaterialStyle.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("Color scheme", selection: $appearance.colorScheme) {
                ForEach(SchemeChoice.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            ColorPicker("Tint color", selection: $appearance.tint.color, supportsOpacity: false)
            LabeledSlider(title: "Tint strength", value: $appearance.tintStrength, range: 0...1, format: .percent)
            LabeledSlider(title: "Background opacity", value: $appearance.backgroundOpacity, range: 0...1, format: .percent)
            LabeledSlider(title: "Window opacity (including text)", value: $appearance.windowOpacity, range: 0.25...1, format: .percent)
            LabeledSlider(title: "Corner radius", value: $appearance.cornerRadius, range: 0...32, format: .points)
            Toggle("Hairline border", isOn: $appearance.showBorder)
        }

        Section("Text") {
            Picker("Font", selection: Binding(
                get: { appearance.fontFamily ?? "" },
                set: { appearance.fontFamily = $0.isEmpty ? nil : $0 }
            )) {
                Text("System").tag("")
                Divider()
                ForEach(Self.fontFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            if appearance.fontFamily == nil {
                Picker("System design", selection: $appearance.fontDesign) {
                    ForEach(FontDesignChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            LabeledSlider(title: "Size", value: $appearance.fontSize, range: Appearance.fontSizeRange, format: .points, step: 0.5)
            Toggle("Custom text color", isOn: Binding(
                get: { appearance.textColor != nil },
                set: { appearance.textColor = $0 ? RGBAColor(r: 0.95, g: 0.95, b: 0.97) : nil }
            ))
            if appearance.textColor != nil {
                ColorPicker("Text color", selection: Binding(
                    get: { appearance.textColor?.color ?? .white },
                    set: { appearance.textColor = RGBAColor($0) }
                ), supportsOpacity: false)
            }
            ColorPicker("Accent (headings & bullets)", selection: $appearance.accent.color, supportsOpacity: false)
        }

        Section("Layout of content") {
            Picker("Columns", selection: $appearance.columns) {
                Text("Automatic").tag(0)
                ForEach(1...6, id: \.self) { Text("\($0)").tag($0) }
            }
            if appearance.columns == 0 {
                LabeledSlider(title: "Minimum column width", value: $appearance.minColumnWidth, range: 200...600, format: .points)
            }
            Picker("Density", selection: $appearance.density) {
                ForEach(Density.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Draw sections as cards", isOn: $appearance.sectionCards)
            Toggle("Row separators", isOn: $appearance.rowSeparators)
            Toggle("Show header bar (title, filter, controls)", isOn: $appearance.showHeader)
            Toggle("Light backdrop behind images", isOn: $appearance.imageBackdrop)
        }

        Section("Shortcuts") {
            Toggle("Draw keyboard shortcuts as keycaps", isOn: $appearance.keycaps)
            Picker("Modifier style", selection: $appearance.modifierStyle) {
                ForEach(ModifierStyle.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .disabled(!appearance.keycaps)
        }
    }
}

/// A live miniature of the overlay using sample content.
struct AppearancePreview: View {
    let appearance: Appearance
    private static let sample: [CheetSection] = Array((SampleCheets.all().dropFirst().first?.sections ?? []).prefix(3))

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.30, green: 0.36, blue: 0.52), Color(red: 0.62, green: 0.45, blue: 0.40)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ScrollView {
                CheetContentView(
                    sections: Self.sample,
                    style: RenderStyle(appearance: appearance, scale: 0.85)
                )
                .padding(14)
            }
            .scrollDisabled(true)
            .foregroundStyle(appearance.textColor?.color ?? Color.primary)
            .background(GlassBackground(appearance: appearance, blending: .withinWindow))
            .environment(\.colorScheme, appearance.swiftUIScheme ?? .dark)
            .opacity(appearance.windowOpacity)
            .padding(18)
        }
        .clipped()
    }
}

// MARK: - Layout

struct LayoutPane: View {
    @Bindable var model: AppModel

    var body: some View {
        let layout = $model.settings.layout
        Form {
            Section("Position") {
                LabeledContent("Anchor") {
                    AnchorGrid(selection: layout.anchor)
                }
                LabeledSlider(title: "Margin from screen edges", value: layout.margin, range: 0...160, format: .points)
            }
            Section("Size") {
                LabeledSlider(title: "Width", value: layout.widthFraction, range: 0.2...1, format: .percent)
                LabeledSlider(title: "Height", value: layout.heightFraction, range: 0.2...1, format: .percent)
            }
            Section("Display") {
                Picker("Show on", selection: layout.screen) {
                    ForEach(ScreenChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section {
                Toggle("Remember where I drag and resize the overlay", isOn: layout.rememberFrame)
                Toggle("Remember a separate position for each cheet", isOn: layout.perCheetFrames)
                    .disabled(!model.settings.layout.rememberFrame)
                HStack {
                    Button("Forget Remembered Positions") { forgetFrames() }
                    Spacer()
                    Button("Show on Screen") { AppController.shared.overlay.toggleLast() }
                }
            } header: {
                Text("Memory")
            } footer: {
                Text("Drag the overlay by its header, resize it from the bottom-right corner, double-click the header to snap back to the preset.")
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.settings.layout.anchor) { forgetFrames() }
        .onChange(of: model.settings.layout.widthFraction) { forgetFrames() }
        .onChange(of: model.settings.layout.heightFraction) { forgetFrames() }
        .onChange(of: model.settings.layout.margin) { forgetFrames() }
    }

    private func forgetFrames() {
        model.viewState.globalFrame = nil
        for key in model.viewState.cheets.keys {
            model.viewState.cheets[key]?.frame = nil
        }
        AppController.shared.overlay.relayoutIfVisible()
    }
}

struct AnchorGrid: View {
    @Binding var selection: OverlayAnchor
    private let rows: [[OverlayAnchor]] = [[.topLeft, .top, .topRight], [.left, .center, .right], [.bottomLeft, .bottom, .bottomRight]]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(rows[r], id: \.self) { anchor in
                        Button {
                            selection = anchor
                        } label: {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(selection == anchor ? Color.accentColor : Color.primary.opacity(0.12))
                                .frame(width: 30, height: 18)
                        }
                        .buttonStyle(.plain)
                        .help(String(describing: anchor))
                    }
                }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.2)))
    }
}
