import AppKit
import CheetCore
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Bindable var importModel: ImportModel
    let onClose: () -> Void

    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            sourceBar
            Divider()
            HSplitView {
                sourcePane
                    .frame(minWidth: 320, idealWidth: 460)
                previewPane
                    .frame(minWidth: 380, idealWidth: 560)
            }
            Divider()
            bottomBar
        }
        .frame(minWidth: 900, minHeight: 580)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL, .html, .plainText], isTargeted: $dropTargeted, perform: handleDrop)
        .task(id: importModel.parseKey) {
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            importModel.reparse()
        }
    }

    // MARK: Top bar

    private var sourceBar: some View {
        HStack(spacing: 8) {
            Button {
                importModel.pasteFromClipboard()
            } label: {
                Label("Paste Clipboard", systemImage: "doc.on.clipboard")
            }
            Button {
                importModel.chooseFile()
            } label: {
                Label("Open File…", systemImage: "folder")
            }
            HStack(spacing: 4) {
                Image(systemName: "globe").foregroundStyle(.secondary)
                TextField("Import from a web page URL…", text: $importModel.urlString)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180, maxWidth: 320)
                    .onSubmit(openWebImport)
                Button("Fetch…", action: openWebImport)
                    .help("Opens Import from URL, where you pick which parts of the page to keep")
                Button {
                    AppController.shared.openCheatographyBrowser()
                } label: {
                    Image(systemName: "books.vertical")
                }
                .help("Browse Cheatography")
            }
            Spacer(minLength: 8)
            Picker("Format", selection: $importModel.format) {
                ForEach(ImportFormat.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Panes

    private var sourcePane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                paneLabel("SOURCE")
                Spacer()
                if importModel.effectiveFormat == .delimited {
                    Picker("Delimiter", selection: $importModel.delimiter) {
                        Text("Detect").tag(Delimiter?.none)
                        ForEach(Delimiter.allCases, id: \.self) { Text($0.label).tag(Delimiter?.some($0)) }
                    }
                    .fixedSize()
                    .controlSize(.small)
                    Picker("Header", selection: $importModel.header) {
                        ForEach(HeaderMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .fixedSize()
                    .controlSize(.small)
                }
                if importModel.effectiveFormat == .html || importModel.effectiveFormat == .markdown {
                    Toggle("Keep paragraphs", isOn: $importModel.keepParagraphs)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .help("Turn off to keep only headings, tables, lists and code")
                }
            }
            SourceTextView(text: $importModel.source) { url in importModel.load(file: url) }
                .overlay(alignment: .topLeading) {
                    if importModel.source.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Paste or type Markdown, HTML, CSV/TSV or JSON…")
                            Text("…or drop a file here, or fetch a URL above.")
                            Text("")
                            Text("# My Cheet\n## Section\n| Key | Action |\n|---|---|\n| ⌘K | Do the thing |\n\n- `cmd` — description")
                                .font(.system(size: 11.5, design: .monospaced))
                        }
                        .foregroundStyle(.tertiary)
                        .padding(12)
                        .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        }
        .padding(12)
    }

    private var previewPane: some View {
        let appearance = importModel.appModel.settings.appearance
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                paneLabel("PREVIEW")
                Spacer()
                if let result = importModel.result {
                    Text("\(result.detectedFormat.shortLabel) · \(result.cheet.sections.count) sections · \(result.cheet.entryCount) entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ZStack {
                LinearGradient(colors: [Color(red: 0.22, green: 0.26, blue: 0.40), Color(red: 0.45, green: 0.33, blue: 0.36)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Group {
                    if let result = importModel.result, let preview = importModel.previewCheet {
                        VStack(spacing: 0) {
                            HStack {
                                Text(result.cheet.title)
                                    .font(appearance.font(size: 14, weight: .semibold))
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
                            ScrollView {
                                CheetContentView(sections: preview.visibleSections, style: RenderStyle(appearance: preview.appearance ?? appearance, scale: 0.92, copyOnClick: false))
                                    .padding(14)
                            }
                        }
                        .foregroundStyle(appearance.textColor?.color ?? Color.primary)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: importModel.errorMessage == nil ? "text.badge.plus" : "exclamationmark.triangle")
                                .font(.system(size: 30))
                                .foregroundStyle(.secondary)
                            Text(importModel.errorMessage ?? "Your cheet will appear here as you paste.")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .background(GlassBackground(appearance: appearance, blending: .withinWindow))
                .environment(\.colorScheme, appearance.swiftUIScheme ?? .dark)
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(12)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            TextField("Title", text: $importModel.title, prompt: Text(importModel.result?.documentTitle ?? importModel.fallbackTitle ?? "Cheet title"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)

            HStack(spacing: 6) {
                Text("Shortcut").foregroundStyle(.secondary)
                Picker("Shortcut", selection: Binding(
                    get: { importModel.hotkey.mode },
                    set: { importModel.hotkey = HotkeyAssignment(mode: $0, combo: importModel.hotkey.combo) }
                )) {
                    Text(automaticLabel).tag(HotkeyAssignment.Mode.automatic)
                    Text("Custom").tag(HotkeyAssignment.Mode.custom)
                    Text("None").tag(HotkeyAssignment.Mode.disabled)
                }
                .labelsHidden()
                .fixedSize()
                if importModel.hotkey.mode == .custom {
                    HotkeyRecorder(combo: Binding(
                        get: { importModel.hotkey.combo },
                        set: { importModel.hotkey = HotkeyAssignment(mode: .custom, combo: $0) }
                    ))
                }
            }

            if let notice = importModel.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("Cancel", role: .cancel, action: onClose)
                .keyboardShortcut(.cancelAction)
            Button(importModel.isEditing ? "Save Changes" : "Create Cheet") {
                importModel.reparse()
                if let id = importModel.commit() {
                    onClose()
                    if !importModel.isEditing {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            AppController.shared.overlay.show(cheetID: id)
                        }
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(importModel.result == nil)
        }
        .padding(12)
    }

    private func openWebImport() {
        AppController.shared.openWebImport(WebFetcher.normalizedURL(importModel.urlString))
    }

    private var automaticLabel: String {
        let settings = importModel.appModel.settings.hotkeys
        let position = importModel.editingID.flatMap { importModel.appModel.index(of: $0) } ?? importModel.appModel.cheets.count
        if settings.autoNumbering, let combo = HotkeyResolver.automaticCombo(forIndex: position, base: settings.baseModifiers) {
            return "Automatic (\(combo.displayString))"
        }
        return "Automatic"
    }

    private func paneLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    // MARK: Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { importModel.load(file: url) }
            }
            return true
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.html.identifier) }) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.html.identifier) { data, _ in
                guard let data, let html = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async {
                    importModel.source = html
                    importModel.format = .html
                }
            }
            return true
        }
        if let provider = providers.first(where: { $0.canLoadObject(ofClass: String.self) }) {
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                guard let text else { return }
                DispatchQueue.main.async {
                    importModel.source = text
                    importModel.format = .auto
                }
            }
            return true
        }
        return false
    }
}

/// Plain-text editor with smart quotes/dashes disabled (they would corrupt Markdown tables),
/// that also accepts dropped files.
struct SourceTextView: NSViewRepresentable {
    @Binding var text: String
    var onFileDrop: (URL) -> Void

    final class DropTextView: NSTextView {
        var onFileDrop: ((URL) -> Void)?

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
               let url = urls.first {
                onFileDrop?(url)
                return true
            }
            return super.performDragOperation(sender)
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let textView = DropTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.backgroundColor = .textBackgroundColor
        textView.string = text
        textView.delegate = context.coordinator
        textView.onFileDrop = onFileDrop

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? DropTextView else { return }
        context.coordinator.parent = self
        textView.onFileDrop = onFileDrop
        if textView.string != text {
            textView.string = text
            textView.scrollToBeginningOfDocument(nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceTextView
        init(parent: SourceTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
