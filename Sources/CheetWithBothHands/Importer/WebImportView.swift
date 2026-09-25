import AppKit
import CheetCore
import SwiftUI

/// "Import from URL": fetch a page, pick which extracted elements to keep, preview, create.
struct WebImportView: View {
    @Bindable var model: WebImportModel
    let onClose: () -> Void

    @FocusState private var urlFocused: Bool
    @State private var copiedBookmarklet = false

    var body: some View {
        VStack(spacing: 0) {
            urlBar
            Divider()
            if let document = model.document, !document.sections.isEmpty {
                HSplitView {
                    elementPane(document)
                        .frame(minWidth: 360, idealWidth: 430)
                    previewPane
                        .frame(minWidth: 420, idealWidth: 620)
                }
            } else {
                emptyState
            }
            Divider()
            bottomBar
        }
        .frame(minWidth: 900, minHeight: 560)
        .onAppear { if model.urlString.isEmpty { urlFocused = true } }
    }

    // MARK: URL bar

    private var urlBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe").foregroundStyle(.secondary)
            TextField("Page URL — e.g. https://cheatography.com/davechild/cheat-sheets/regular-expressions/", text: $model.urlString)
                .textFieldStyle(.roundedBorder)
                .focused($urlFocused)
                .onSubmit { Task { await model.fetch() } }
            Button(model.document == nil ? "Fetch" : "Reload") { Task { await model.fetch() } }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.urlString.trimmingCharacters(in: .whitespaces).isEmpty || model.isFetching)
            if model.isFetching { ProgressView().controlSize(.small) }
            if let document = model.document, document.hasMainContent {
                Picker("Scope", selection: $model.mainContentOnly) {
                    Text("Main content").tag(true)
                    Text("Whole page").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Read only the page's <main>/<article> region, or everything")
            }
            Button {
                if let url = WebFetcher.normalizedURL(model.urlString) { NSWorkspace.shared.open(url) }
            } label: {
                Image(systemName: "safari")
            }
            .help("Open in your browser")
            .disabled(WebFetcher.normalizedURL(model.urlString) == nil)
            Button {
                AppController.shared.openCheatographyBrowser()
            } label: {
                Label("Browse Cheatography", systemImage: "books.vertical")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Elements

    private func elementPane(_ document: WebDocument) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("ELEMENTS")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Text("\(model.selectedCount) of \(model.totalCount) selected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Spacer()
                Menu("Select") {
                    Button("All") { model.setAll(true) }
                    Button("None") { model.setAll(false) }
                    Button("Tables, Lists & Code Only") { model.selectStructured() }
                    Button("Suggested") { model.useSuggestions() }
                    Divider()
                    Button("Expand All") { model.expanded = Set(document.sections.map(\.id)) }
                    Button("Collapse All") { model.expanded = [] }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Text("\(document.extractorName) · \(document.sections.count) sections. Uncheck anything you don't want; the preview updates live.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(document.sections) { section in
                        // One container per section keeps row identities unique in the lazy stack.
                        VStack(alignment: .leading, spacing: 1) {
                            sectionRow(section)
                            if model.expanded.contains(section.id) {
                                ForEach(Array(section.blocks.enumerated()), id: \.offset) { index, block in
                                    blockRow(block, index: index, in: section)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func sectionRow(_ section: CheetSection) -> some View {
        let state = model.selection.state(of: section)
        let isExpanded = model.expanded.contains(section.id)
        return HStack(spacing: 6) {
            Button {
                if isExpanded { model.expanded.remove(section.id) } else { model.expanded.insert(section.id) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 14, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            TriStateCheckbox(state: state) { model.toggle(section: section) }
            Text(section.title.isEmpty ? "Untitled" : InlineMarkdown.plainText(section.title))
                .fontWeight(.semibold)
                .foregroundStyle(state == .off ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text("\(section.blocks.count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(section: section) }
    }

    private func blockRow(_ block: CheetBlock, index: Int, in section: CheetSection) -> some View {
        let included = model.selection.includes(section.id, block: index)
        let summary = WebDocument.summary(of: block)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            TriStateCheckbox(state: included ? .on : .off) { model.toggle(block: index, in: section) }
            Image(systemName: symbol(for: summary.kind))
                .font(.system(size: 11))
                .frame(width: 16)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(summary.kind.label).font(.caption.weight(.medium))
                    if let count = summary.count {
                        Text(countLabel(summary.kind, count)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !summary.detail.isEmpty {
                    Text(summary.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if case .image(let image) = block {
                RemoteImage(source: image.source, maxHeight: 44, backdrop: true)
                    .frame(maxWidth: 90, alignment: .trailing)
            }
        }
        .opacity(included ? 1 : 0.5)
        .padding(.leading, 40)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(block: index, in: section) }
    }

    private func symbol(for kind: WebDocument.ElementSummary.Kind) -> String {
        switch kind {
        case .table: "tablecells"
        case .list: "list.bullet"
        case .text: "text.alignleft"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .heading: "textformat.size"
        case .image: "photo"
        }
    }

    private func countLabel(_ kind: WebDocument.ElementSummary.Kind, _ count: Int) -> String {
        switch kind {
        case .table: "\(count) row\(count == 1 ? "" : "s")"
        case .list: "\(count) item\(count == 1 ? "" : "s")"
        case .code: "\(count) line\(count == 1 ? "" : "s")"
        default: "\(count)"
        }
    }

    // MARK: Preview

    private var previewPane: some View {
        let preview = model.previewCheet
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PREVIEW")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Spacer()
                if let preview {
                    Text("\(preview.sections.count) sections · \(preview.entryCount) entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            CheetPreview(cheet: preview, appearance: model.appModel.settings.appearance) {
                PreviewMessage(symbol: "checklist.unchecked", message: "Nothing selected yet.")
            }
        }
        .padding(12)
    }

    // MARK: Empty / error state

    private var emptyState: some View {
        VStack(spacing: 14) {
            if model.isFetching {
                ProgressView()
                Text("Fetching \(model.urlString)…").foregroundStyle(.secondary)
            } else if let error = model.errorMessage {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 32)).foregroundStyle(.secondary)
                Text(error).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 480)
            } else {
                Image(systemName: "globe").font(.system(size: 34)).foregroundStyle(.secondary)
                Text("Import a cheet from a web page").font(.title3.weight(.semibold))
                Text("Paste a URL above. Headings, tables, lists and code are picked out as elements you can keep or drop. Markdown, CSV and JSON URLs work too.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 500)
            }
            Divider().frame(width: 360).padding(.vertical, 6)
            HStack(spacing: 10) {
                Button {
                    AppController.shared.openCheatographyBrowser()
                } label: {
                    Label("Browse Cheatography", systemImage: "books.vertical")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(WebImportModel.bookmarklet, forType: .string)
                    copiedBookmarklet = true
                } label: {
                    Label(copiedBookmarklet ? "Bookmarklet Copied" : "Copy Browser Bookmarklet",
                          systemImage: copiedBookmarklet ? "checkmark" : "bookmark")
                }
                .help("Save this as a bookmark's address. Clicking it sends the page you're viewing here.")
            }
            if copiedBookmarklet {
                Text("Create a bookmark in Safari or Chrome and paste this as its address. Click it on any page to import that page.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            TextField("Title", text: $model.title, prompt: Text("Cheet title"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)

            HStack(spacing: 6) {
                Text("Shortcut").foregroundStyle(.secondary)
                Picker("Shortcut", selection: Binding(
                    get: { model.hotkey.mode },
                    set: { model.hotkey = HotkeyAssignment(mode: $0, combo: model.hotkey.combo) }
                )) {
                    Text("Automatic").tag(HotkeyAssignment.Mode.automatic)
                    Text("Custom").tag(HotkeyAssignment.Mode.custom)
                    Text("None").tag(HotkeyAssignment.Mode.disabled)
                }
                .labelsHidden()
                .fixedSize()
                if model.hotkey.mode == .custom {
                    HotkeyRecorder(combo: Binding(
                        get: { model.hotkey.combo },
                        set: { model.hotkey = HotkeyAssignment(mode: .custom, combo: $0) }
                    ))
                }
            }

            if let existing = model.existingCheet {
                Toggle("Update “\(existing.title)”", isOn: $model.replaceExisting)
                    .toggleStyle(.checkbox)
                    .help("This page was imported before. Replace that cheet's content (its layout is kept) instead of adding another.")
            } else if let credit = model.document?.attribution {
                Text(credit).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("Cancel", role: .cancel, action: onClose)
                .keyboardShortcut(.cancelAction)
            Button(model.existingCheet != nil && model.replaceExisting ? "Update Cheet" : "Create Cheet") {
                if let id = model.commit() {
                    onClose()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        AppController.shared.overlay.show(cheetID: id)
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled((model.previewCheet?.sections.isEmpty ?? true))
        }
        .padding(12)
    }
}

/// A checkbox that can also show a "some selected" dash.
struct TriStateCheckbox: View {
    let state: ElementSelection.State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(state == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var symbol: String {
        switch state {
        case .on: "checkmark.square.fill"
        case .mixed: "minus.square.fill"
        case .off: "square"
        }
    }
}
