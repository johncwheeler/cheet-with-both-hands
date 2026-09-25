import AppKit
import CheetCore
import SwiftUI

/// The full cheet inventory: reorder (which also renumbers the automatic hotkeys), rename,
/// assign shortcuts, give a cheet its own look, edit, export or delete.
struct CheetsPane: View {
    @Bindable var model: AppModel
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $navigation.selectedCheetID) {
                    ForEach(Array(model.cheets.enumerated()), id: \.element.id) { index, cheet in
                        CheetListRow(index: index, cheet: cheet, combo: model.combo(forCheet: cheet.id))
                            .tag(cheet.id)
                            .contextMenu { contextMenu(for: cheet) }
                    }
                    .onMove { model.move(from: $0, to: $1) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))

                Divider()
                HStack(spacing: 2) {
                    Menu {
                        Button("New Cheet…") { AppController.shared.openImporter() }
                        Button("New Cheet from Clipboard") { AppController.shared.newCheetFromClipboard() }
                        Button("Import from URL…") { AppController.shared.openWebImport() }
                        Button("Browse Cheatography…") { AppController.shared.openCheatographyBrowser() }
                        Button("Import Files…") { AppController.shared.importFiles() }
                        Divider()
                        Button("Restore Sample Cheets") { model.restoreSamples() }
                    } label: {
                        Image(systemName: "plus").frame(width: 22, height: 20)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Add cheets")

                    Button {
                        if let id = navigation.selectedCheetID { delete(id) }
                    } label: {
                        Image(systemName: "minus").frame(width: 22, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .disabled(navigation.selectedCheetID == nil)
                    .help("Delete the selected cheet")

                    Button {
                        if let id = navigation.selectedCheetID, let copy = model.duplicate(id) {
                            navigation.selectedCheetID = copy
                        }
                    } label: {
                        Image(systemName: "plus.square.on.square").frame(width: 22, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .disabled(navigation.selectedCheetID == nil)
                    .help("Duplicate")

                    Spacer()
                    Text("Drag to reorder")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .frame(width: 270)

            Divider()

            if let id = navigation.selectedCheetID, model.cheet(id: id) != nil {
                CheetInspector(model: model, cheetID: id, onDelete: { delete(id) })
                    .id(id)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle").font(.system(size: 36)).foregroundStyle(.tertiary)
                    Text(model.cheets.isEmpty ? "No cheets yet" : "Select a cheet").foregroundStyle(.secondary)
                    if model.cheets.isEmpty {
                        Button("New Cheet…") { AppController.shared.openImporter() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for cheet: Cheet) -> some View {
        Button("Show") { AppController.shared.overlay.show(cheetID: cheet.id) }
        Button("Edit Content…") { AppController.shared.editCheet(cheet.id) }
        Button("Duplicate") { model.duplicate(cheet.id) }
        Divider()
        Button("Export as Markdown…") { AppController.shared.exportMarkdown(cheet) }
        Button("Export as JSON…") { AppController.shared.exportJSON(cheet) }
        Divider()
        Button("Delete…", role: .destructive) { delete(cheet.id) }
    }

    private func delete(_ id: UUID) {
        guard let cheet = model.cheet(id: id) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(cheet.title)”?"
        alert.informativeText = "This removes the cheet from your library. Export it first if you might want it back."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let index = model.index(of: id) ?? 0
        if AppController.shared.overlay.state.cheetID == id { AppController.shared.overlay.hide() }
        model.delete(id)
        if !model.cheets.isEmpty {
            navigation.selectedCheetID = model.cheets[min(index, model.cheets.count - 1)].id
        } else {
            navigation.selectedCheetID = nil
        }
    }
}

private struct CheetListRow: View {
    let index: Int
    let cheet: Cheet
    let combo: KeyCombo?

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(cheet.title).lineLimit(1)
                Text("\(cheet.sections.count) sections · \(cheet.entryCount) entries")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if cheet.appearance != nil {
                Image(systemName: "paintpalette.fill").font(.caption2).foregroundStyle(.secondary).help("Custom appearance")
            }
            if let combo {
                Text(combo.displayString)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct CheetInspector: View {
    @Bindable var model: AppModel
    let cheetID: UUID
    let onDelete: () -> Void
    @State private var editingAppearance = false

    var body: some View {
        let cheet = model.binding(forCheet: cheetID)
        let value = cheet.wrappedValue
        Form {
            Section {
                TextField("Title", text: cheet.title)
                LabeledContent("Contents", value: "\(value.sections.count) sections · \(value.entryCount) entries")
                if let source = value.source {
                    LabeledContent("Imported as", value: source.format.shortLabel)
                    if let origin = source.origin {
                        LabeledContent("From") {
                            HStack(spacing: 6) {
                                Text(origin).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                                if let url = URL(string: origin), url.scheme?.hasPrefix("http") == true {
                                    Button {
                                        NSWorkspace.shared.open(url)
                                    } label: {
                                        Image(systemName: "arrow.up.right.square")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Open the source page")
                                    Button("Re-import…") { AppController.shared.openWebImport(url) }
                                        .controlSize(.small)
                                        .help("Fetch the page again and choose elements (updates this cheet)")
                                }
                            }
                        }
                    }
                    if let credit = source.attribution {
                        LabeledContent("Credit", value: credit)
                    }
                }
                LabeledContent("Last changed", value: value.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }

            Section("Shortcut") {
                CheetHotkeyEditor(model: model, cheet: cheet)
                if let index = model.index(of: cheetID), index >= HotkeyResolver.automaticSlots, value.hotkey.mode == .automatic {
                    Text("Only the first ten cheets get number shortcuts. Drag this cheet higher, give it a custom shortcut, or use the cheet picker.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Appearance") {
                Toggle("Use a custom look for this cheet", isOn: Binding(
                    get: { value.appearance != nil },
                    set: { on in cheet.wrappedValue.appearance = on ? model.settings.appearance : nil }
                ))
                if value.appearance != nil {
                    Button("Edit This Cheet's Appearance…") { editingAppearance = true }
                }
            }

            Section {
                HStack {
                    Button("Show") { AppController.shared.overlay.show(cheetID: cheetID) }
                    Button("Edit Layout") { AppController.shared.overlay.editLayout(cheetID: cheetID) }
                    Button("Edit Content…") { AppController.shared.editCheet(cheetID) }
                    Spacer(minLength: 0)
                }
                HStack {
                    Menu("Export") {
                        Button("Markdown…") { AppController.shared.exportMarkdown(value) }
                        Button("JSON (keeps layout & styles)…") { AppController.shared.exportJSON(value) }
                    }
                    .fixedSize()
                    Spacer()
                    Button("Delete…", role: .destructive, action: onDelete)
                }
            }

            Section {
                ForEach(value.sections) { section in
                    HStack {
                        Button {
                            guard let index = cheet.wrappedValue.sections.firstIndex(where: { $0.id == section.id }) else { return }
                            cheet.wrappedValue.sections[index].layout.isHidden.toggle()
                        } label: {
                            Image(systemName: section.layout.isHidden ? "eye.slash" : "eye")
                                .foregroundStyle(section.layout.isHidden ? .secondary : .primary)
                                .frame(width: 20)
                        }
                        .buttonStyle(.plain)
                        .help(section.layout.isHidden ? "Show this card" : "Hide this card")
                        Text(section.title.isEmpty ? "(untitled)" : InlineMarkdown.plainText(section.title))
                            .foregroundStyle(section.title.isEmpty || section.layout.isHidden ? .secondary : .primary)
                        if !section.layout.style.isDefault || section.layout.width != .auto || section.layout.height != nil {
                            Image(systemName: "paintbrush.pointed.fill").font(.caption2).foregroundStyle(.tertiary)
                                .help("Custom size or style")
                        }
                        Spacer()
                        Text("\(section.entryCount)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            } header: {
                HStack {
                    Text("Cards")
                    Spacer()
                    Button("Reset Layout") {
                        for index in cheet.wrappedValue.sections.indices {
                            cheet.wrappedValue.sections[index].layout = SectionLayout()
                        }
                    }
                    .controlSize(.small)
                    .disabled(value.sections.allSatisfy { $0.layout.isDefault })
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $editingAppearance) {
            CheetAppearanceEditor(model: model, cheetID: cheetID)
        }
    }
}

private struct CheetAppearanceEditor: View {
    @Bindable var model: AppModel
    let cheetID: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let binding = Binding<Appearance>(
            get: { model.cheet(id: cheetID)?.appearance ?? model.settings.appearance },
            set: { newValue in
                guard var cheet = model.cheet(id: cheetID) else { return }
                cheet.appearance = newValue
                model.update(cheet)
            }
        )
        VStack(spacing: 0) {
            Form {
                Section {
                    AppearancePreview(appearance: binding.wrappedValue)
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets())
                }
                AppearanceForm(appearance: binding)
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Copy Global Appearance") { binding.wrappedValue = model.settings.appearance }
                Button("Show on Screen") { AppController.shared.overlay.show(cheetID: cheetID) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 680)
    }
}
