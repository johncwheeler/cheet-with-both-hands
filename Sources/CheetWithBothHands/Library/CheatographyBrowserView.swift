import AppKit
import CheetCore
import SwiftUI

struct CheatographyBrowserView: View {
    @Bindable var model: CheatographyBrowserModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
            Divider()
            results
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 540)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search Cheatography", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await model.search() } }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.07)))
            .padding(10)

            List {
                Section("Explore") {
                    ForEach(CheatographyCatalog.Feed.allCases, id: \.self) { feed in
                        sourceRow(.feed(feed), title: feed.label, symbol: feed.symbol)
                    }
                }
                Section("Categories") {
                    ForEach(CheatographyCatalog.Category.allCases, id: \.self) { category in
                        sourceRow(.category(category), title: category.label, symbol: category.symbol)
                    }
                }
                if !model.popularTags.isEmpty {
                    Section("Popular Tags") {
                        ForEach(model.popularTags, id: \.slug) { tag in
                            sourceRow(.tag(slug: tag.slug, name: tag.name), title: tag.name, symbol: "number")
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            Text("Cheets from cheatography.com are made by its community. Credit is kept with each import.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(10)
        }
    }

    private func sourceRow(_ source: CheatographyCatalog.Source, title: String, symbol: String) -> some View {
        let selected = model.source == source
        return Button {
            Task { await model.load(source) }
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .foregroundStyle(selected ? Color.accentColor : Color.primary)
        .fontWeight(selected ? .semibold : .regular)
    }

    // MARK: Results

    private var results: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.isLoading && model.items.isEmpty {
                ProgressView("Loading \(model.source.title)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.errorMessage, model.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Try Again") { Task { await model.load(model.source) } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.items.isEmpty {
                Text("No cheat sheets here.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if let group = model.tagGroups.first {
                            tagStrip(group)
                        }
                        ForEach(model.items) { item in
                            CatalogRow(
                                item: item,
                                isChecked: model.checked.contains(item.id),
                                inLibrary: model.isInLibrary(item),
                                onToggle: { model.toggleChecked(item) },
                                onImport: { model.openImporter(for: item) },
                                onTag: { tag in Task { await model.load(.tag(slug: tag.slug, name: tag.name)) } }
                            )
                        }
                        if model.nextPageURL != nil {
                            Group {
                                if model.isLoadingMore {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Button("Load More") { Task { await model.loadMore() } }
                                }
                            }
                            .padding(.vertical, 12)
                            .onAppear { Task { await model.loadMore() } }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.source.title).font(.title3.weight(.semibold))
                if let heading = model.heading {
                    Text(heading).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let progress = model.bulkProgress {
                ProgressView(value: Double(progress.done), total: Double(progress.total))
                    .frame(width: 120)
                Text("Importing \(progress.done + 1 > progress.total ? progress.total : progress.done + 1) of \(progress.total)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let status = model.statusMessage {
                Label(status, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !model.checked.isEmpty {
                Button("Clear") { model.checked = [] }
                Button("Import \(model.checked.count) Selected") { Task { await model.importChecked() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.bulkProgress != nil)
            }
            Button {
                NSWorkspace.shared.open(model.source.url)
            } label: {
                Image(systemName: "safari")
            }
            .help("Open this list in your browser")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func tagStrip(_ group: (title: String, tags: [CatalogTag])) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(group.tags, id: \.slug) { tag in
                    Button {
                        Task { await model.load(.tag(slug: tag.slug, name: tag.name)) }
                    } label: {
                        Text(tag.count.map { "\(tag.name) \($0)" } ?? tag.name)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 6)
    }
}

private struct CatalogRow: View {
    let item: CatalogItem
    let isChecked: Bool
    let inLibrary: Bool
    let onToggle: () -> Void
    let onImport: () -> Void
    let onTag: (CatalogTag) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TriStateCheckbox(state: isChecked ? .on : .off, action: onToggle)
                .padding(.top, 2)
                .disabled(inLibrary)
                .opacity(inLibrary ? 0.3 : 1)
                .help(inLibrary ? "Already in your library" : "Select for bulk import")

            AsyncImage(url: item.thumbnailURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color.primary.opacity(0.06))
                    .overlay(Image(systemName: "doc.richtext").foregroundStyle(.tertiary))
            }
            .frame(width: 68, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.displayTitle).font(.headline).lineLimit(1)
                    if item.kind != "Cheat Sheet" { badge(item.kind, color: .blue) }
                    if inLibrary { badge("In Library", color: .green) }
                }
                Text(byline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !item.summary.isEmpty {
                    Text(item.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let rating = item.rating {
                        StarRating(value: rating, count: item.ratingCount)
                    }
                    ForEach(item.tags.prefix(4), id: \.slug) { tag in
                        Button("#\(tag.name)") { onTag(tag) }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Button(inLibrary ? "Import Again…" : "Import…", action: onImport)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Open in Browser") { NSWorkspace.shared.open(item.url) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.06 : 0.03)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onImport)
    }

    private var byline: String {
        var parts = ["by \(item.author)"]
        if let pages = item.pageCount { parts.append("\(pages) page\(pages == 1 ? "" : "s")") }
        if let updated = item.updated { parts.append(updated) }
        return parts.joined(separator: " · ")
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}

private struct StarRating: View {
    let value: Double
    let count: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { index in
                let fill = value - Double(index)
                Image(systemName: fill >= 0.75 ? "star.fill" : (fill >= 0.25 ? "star.leadinghalf.filled" : "star"))
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }
            Text("(\(count))").font(.caption2).foregroundStyle(.secondary).padding(.leading, 2)
        }
        .help(String(format: "Rated %.1f by %d people", value, count))
    }
}
