import SwiftUI

struct IssueBody: View {
    let issue: DigestIssue
    let section: DigestSection
    let onReading: (() -> Void)?
    @EnvironmentObject private var model: DigestModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var page: Int
    @State private var sheet: PresentedSheet?
    @State private var didQualify = false

    init(issue: DigestIssue, section: DigestSection, page: Int = 0, onReading: (() -> Void)? = nil) {
        self.issue = issue
        self.section = section
        self.onReading = onReading
        _page = State(initialValue: page)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let banner = model.banner {
                Text(banner)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.18))
            }
            SectionPager(
                section: section,
                dateLine: ChineseDate.string(from: issue.date),
                page: pageBinding,
                accent: SectionAccent.color(for: section.name),
                onWeb: { url in
                    sheet = .web(WebLink(url: url))
                },
                onGlossary: { entry in
                    sheet = .glossary(entry)
                },
                onReadingScroll: onReading == nil ? nil : qualifyReading
            )
            .id(section.name)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(section.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await model.refresh() }
        .sheet(item: $sheet) { presented in
            SheetContent(presented: presented)
        }
        .task(id: readingPage) {
            guard readingPage != nil, !didQualify else { return }
            do {
                try await Task.sleep(for: .seconds(8))
                if !Task.isCancelled { qualifyReading() }
            } catch {
                return
            }
        }
    }

    private var readingPage: Int? {
        guard onReading != nil, scenePhase == .active, sheet == nil,
              section.items.indices.contains(page) else { return nil }
        return page
    }

    private func qualifyReading() {
        guard readingPage != nil, !didQualify else { return }
        didQualify = true
        onReading?()
    }

    private var pageBinding: Binding<Int> {
        Binding(
            get: { min(page, max(section.entryCount - 1, 0)) },
            set: { page = $0 }
        )
    }
}

private enum SectionAccent {
    static func color(for name: String) -> Color {
        switch name {
        case "每日一图":
            return Color(red: 0.72, green: 0.40, blue: 0.16)
        case "国际政治与时事":
            return Color(red: 0.13, green: 0.28, blue: 0.55)
        case "经济与市场":
            return Color(red: 0.09, green: 0.42, blue: 0.34)
        case "科技与人工智能":
            return Color(red: 0.30, green: 0.22, blue: 0.62)
        case "社会资讯", "社会与荒诞":
            return Color(red: 0.62, green: 0.26, blue: 0.30)
        case "科学与体育":
            return Color(red: 0.08, green: 0.40, blue: 0.52)
        case "影视与明星":
            return Color(red: 0.55, green: 0.16, blue: 0.36)
        case "书籍与作家":
            return Color(red: 0.45, green: 0.28, blue: 0.14)
        case "天涯海角":
            return Color(red: 0.14, green: 0.38, blue: 0.44)
        case "美女与野兽":
            return Color(red: 0.50, green: 0.20, blue: 0.28)
        case "维基漫游":
            return Color(red: 0.16, green: 0.34, blue: 0.46)
        case "笑话":
            return Color(red: 0.72, green: 0.42, blue: 0.10)
        default:
            return Color(red: 0.22, green: 0.30, blue: 0.42)
        }
    }

    static func symbol(for name: String) -> String {
        switch name {
        case "每日一图":
            return "sun.max"
        case "国际政治与时事":
            return "globe.asia.australia"
        case "经济与市场":
            return "chart.line.uptrend.xyaxis"
        case "科技与人工智能":
            return "cpu"
        case "社会资讯", "社会与荒诞":
            return "person.2"
        case "科学与体育":
            return "sportscourt"
        case "影视与明星":
            return "film"
        case "书籍与作家":
            return "book"
        case "天涯海角":
            return "map"
        case "美女与野兽":
            return "pawprint"
        case "维基漫游":
            return "book.closed"
        case "笑话":
            return "quote.opening"
        default:
            return "photo"
        }
    }
}

private struct SectionPager: View {
    let section: DigestSection
    let dateLine: String
    @Binding var page: Int
    let accent: Color
    let onWeb: (URL) -> Void
    let onGlossary: (GlossaryEntry) -> Void
    var onReadingScroll: (() -> Void)?

    var body: some View {
        TabView(selection: $page) {
            ForEach(0..<section.entryCount, id: \.self) { index in
                pageView(at: index)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func pageView(at index: Int) -> some View {
        let label = "\(index + 1) / \(max(section.entryCount, 1))"
        if section.name == "笑话", section.jokes.indices.contains(index) {
            jokePage(section.jokes[index], label: label)
        } else if let photo = section.photo {
            photoPage(photo, label: label)
        } else if let place = section.place {
            placePage(place, label: label)
        } else if section.name == "美女与野兽", section.gallery.indices.contains(index) {
            galleryPage(section.gallery[index], label: label)
        } else if let wiki = section.wiki {
            wikiPage(wiki, label: label)
        } else if section.items.indices.contains(index) {
            newsPage(section.items[index], label: label, isSelected: index == page)
        }
    }

    private func newsPage(_ item: DigestItem, label: String, isSelected: Bool) -> some View {
        MagazineCard(
            kicker: section.displayName,
            title: item.headline,
            dateLine: dateLine,
            picture: item.image,
            accent: accent,
            symbol: SectionAccent.symbol(for: section.name),
            pageLabel: label,
            onReadingScroll: isSelected ? onReadingScroll : nil
        ) {
            NewsImportanceBadge(importance: item.importance)
            Text(item.summary)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            SourceButtons(sources: item.sources, onOpen: onWeb)
            GlossaryBlock(entries: item.glossary, onSelect: onGlossary)
            if let credit = item.image?.credit {
                creditLine(credit)
            }
            footnote("新闻摘要据公开报道整理。点来源阅读原文，点蓝色名词查看解释。")
        }
    }

    private func photoPage(_ photo: PhotoOfDay, label: String) -> some View {
        MagazineCard(
            kicker: section.displayName,
            title: photo.title,
            dateLine: dateLine,
            picture: photo.image,
            accent: accent,
            symbol: SectionAccent.symbol(for: section.name),
            pageLabel: label
        ) {
            ForEach(paragraphs(photo.interpretation), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            SourceButtons(sources: photo.sources, onOpen: onWeb)
            creditLine(photo.image.credit)
        }
    }

    private func placePage(_ place: PlaceEssay, label: String) -> some View {
        MagazineCard(
            kicker: section.displayName,
            title: place.name,
            dateLine: dateLine,
            picture: place.photos.first?.picture,
            accent: accent,
            symbol: SectionAccent.symbol(for: section.name),
            pageLabel: label
        ) {
            if let first = place.photos.first {
                if let caption = first.caption {
                    Text(caption)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                creditLine(first.credit)
            }
            ForEach(Array(place.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            ForEach(Array(place.photos.dropFirst())) { photo in
                DigestPhoto(picture: photo.picture, accent: accent, symbol: "map", framing: .full)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                if let caption = photo.caption {
                    Text(caption)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                creditLine(photo.credit)
            }
        }
    }

    private func galleryPage(_ item: GalleryItem, label: String) -> some View {
        MagazineCard(
            kicker: item.kindLabel,
            title: item.caption,
            dateLine: dateLine,
            picture: item.image,
            accent: accent,
            symbol: item.kind == "animal" ? "pawprint" : "person",
            pageLabel: label,
            framing: .full
        ) {
            creditLine(item.image.credit)
            if let source = item.source, let url = source.webURL {
                Button {
                    onWeb(url)
                } label: {
                    Label(source.name, systemImage: "safari")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func wikiPage(_ wiki: WikiArticle, label: String) -> some View {
        MagazineCard(
            kicker: section.displayName,
            title: wiki.title,
            dateLine: dateLine,
            picture: wiki.images.first,
            accent: accent,
            symbol: SectionAccent.symbol(for: section.name),
            pageLabel: label,
            framing: .hero
        ) {
            Text(wiki.originalTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(wiki.tagline)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(paragraphs(wiki.body), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let credit = wiki.images.first?.credit {
                creditLine(credit)
            }
            ForEach(Array(wiki.images.dropFirst().enumerated()), id: \.offset) { _, picture in
                DigestPhoto(picture: picture, accent: accent, symbol: SectionAccent.symbol(for: section.name), framing: .hero)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                creditLine(picture.credit)
            }
            if let url = wiki.webURL {
                Button {
                    onWeb(url)
                } label: {
                    Label("阅读维基原文", systemImage: "safari")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func jokePage(_ joke: JokeItem, label: String) -> some View {
        MagazineCard(
            kicker: section.displayName,
            title: joke.authorName,
            dateLine: dateLine,
            picture: nil,
            accent: accent,
            symbol: "quote.opening",
            pageLabel: label,
            jokeStyle: true
        ) {
            Text(joke.text)
                .font(.system(.title3, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let translation = joke.translation, !translation.isEmpty {
                Text(translation)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let note = joke.note, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = joke.postURL {
                Button {
                    onWeb(url)
                } label: {
                    Text("\(joke.authorName)  \(joke.handle)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开 \(joke.authorName) 的帖子")
            }
            footnote("这些段子来自 X。点作者名字可打开原帖。")
        }
    }

    private func creditLine(_ credit: String) -> some View {
        Text(credit)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func paragraphs(_ text: String) -> [(offset: Int, element: String)] {
        Array(text.components(separatedBy: "\n\n").enumerated())
    }
}

private struct MagazineCard<Content: View>: View {
    let kicker: String
    let title: String
    let dateLine: String
    let picture: DigestPicture?
    let accent: Color
    let symbol: String
    let pageLabel: String
    var framing: PhotoFraming = .hero
    var jokeStyle: Bool = false
    var onReadingScroll: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let cardHeight = max(geo.size.height - 36, 320)
            let hero = min(cardHeight * (framing == .full ? 0.64 : 0.52), 520)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        DigestPhoto(
                            picture: picture,
                            accent: accent,
                            symbol: symbol,
                            fillsFrame: true,
                            framing: framing
                        )
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.15), .black.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: hero * 0.62)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .center, spacing: 8) {
                                Text(kicker)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(accent, in: Capsule())
                                Text(dateLine)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(pageLabel)
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                            Text(title)
                                .font(.title.weight(.bold))
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.65)
                                .fixedSize(horizontal: false, vertical: true)
                                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                        }
                        .padding(18)
                        .allowsHitTesting(false)
                    }
                    .frame(height: hero)
                    .clipped()

                    VStack(alignment: .leading, spacing: 16) {
                        content()
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(alignment: .top) {
                    if onReadingScroll != nil {
                        GeometryReader { geometry in
                            Color.clear.preference(key: ReadingOffset.self,
                                                   value: geometry.frame(in: .named("articleScroll")).minY)
                        }
                        .frame(height: 0)
                    }
                }
            }
            .coordinateSpace(name: "articleScroll")
            .onPreferenceChange(ReadingOffset.self) { offset in
                if offset < -12 { onReadingScroll?() }
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(jokeStyle ? Color.jokePaper : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                if jokeStyle {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            .frame(width: min(geo.size.width - 24, 760), height: cardHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
        }
    }
}

private struct ReadingOffset: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

struct ItemDetailView: View {
    let sectionName: String
    let item: DigestItem
    @State private var sheet: PresentedSheet?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(sectionName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(item.headline)
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                NewsImportanceBadge(importance: item.importance)
                if let picture = item.image {
                    DigestPhoto(picture: picture, framing: .full)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text(picture.credit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(item.summary)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                SourceButtons(sources: item.sources) { url in
                    sheet = .web(WebLink(url: url))
                }
                GlossaryBlock(entries: item.glossary) { entry in
                    sheet = .glossary(entry)
                }
                Text("点蓝色名词可再看一遍说明。来源在 App 内的 Safari 视图中打开。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("正文")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { presented in
            SheetContent(presented: presented)
        }
    }
}

struct ArchiveView: View {
    @EnvironmentObject private var model: DigestModel
    @State private var grouping = Grouping.date
    @State private var category: String?
    @State private var scanAttempt = 0
    @State private var completedScan: Scan?

    private enum Grouping: String, CaseIterable {
        case date = "按日期"
        case category = "按栏目"
    }

    private struct Scan: Equatable {
        let entries: [IndexEntry]
        let attempt: Int
    }

    private var entries: [IndexEntry] { model.index?.issues ?? [] }

    private var categories: [String] {
        var seen: Set<String> = []
        return entries.flatMap { model.sectionNames(in: $0) ?? [] }
            .map(archiveCategoryName)
            .filter { seen.insert($0).inserted }
    }

    private var filteredEntries: [IndexEntry] {
        if grouping == .date { return entries }
        guard let category else { return [] }
        return entries.filter { entry in
            model.sectionNames(in: entry)?.contains { archiveCategoryName($0) == category } == true
        }
    }

    var body: some View {
        let scan = Scan(entries: entries, attempt: scanAttempt)

        List {
            Picker("查看方式", selection: $grouping) {
                ForEach(Grouping.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if entries.isEmpty {
                ContentUnavailableView(
                    "还没有往期",
                    systemImage: "books.vertical",
                    description: Text("下拉可重新获取目录。")
                )
            } else {
                if grouping == .category {
                    categoryControls(scan: scan)
                }
                Section {
                    ForEach(filteredEntries) { entry in
                        NavigationLink(value: ArchiveDestination(
                            date: entry.date,
                            category: grouping == .category ? category : nil
                        )) {
                            editionRow(entry)
                        }
                    }
                }
            }
        }
        .navigationTitle("往期")
        .navigationDestination(for: ArchiveDestination.self) { destination in
            ArchivedIssueView(date: destination.date, category: destination.category)
        }
        .task(id: grouping == .category ? scan : nil) {
            guard grouping == .category else { return }
            await model.loadArchiveSections(scan.entries)
            if !Task.isCancelled { completedScan = scan }
        }
        .onChange(of: categories, initial: true) { _, available in
            if let category, available.contains(category) { return }
            category = available.first
        }
        .refreshable {
            await model.refresh()
            scanAttempt += 1
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                RefreshButton()
            }
        }
    }

    private func categoryControls(scan: Scan) -> some View {
        let unavailable = entries.count { model.sectionNames(in: $0) == nil }
        return Section {
            if !categories.isEmpty {
                Picker("栏目", selection: $category) {
                    ForEach(categories, id: \.self) { name in
                        Text(name).tag(Optional(name))
                    }
                }
                .pickerStyle(.menu)
            }

            if unavailable > 0 {
                if completedScan == scan {
                    Button {
                        scanAttempt += 1
                    } label: {
                        Label("\(unavailable) 期的栏目暂不可用，重试", systemImage: "arrow.clockwise")
                    }
                } else {
                    ProgressView("正在查找各期栏目")
                }
            }
        }
    }

    private func editionRow(_ entry: IndexEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ChineseDate.string(from: entry.date)).font(.headline)
                if entry.date == entries.first?.date {
                    Text("最新")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.16), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
            Text(entry.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct ArchiveDestination: Hashable {
    let date: String
    let category: String?
}

private func archiveCategoryName(_ name: String) -> String {
    name == "社会资讯" ? "社会与荒诞" : DigestSection.displayName(for: name)
}

struct ArchivedIssueView: View {
    let date: String
    let category: String?
    @EnvironmentObject private var model: DigestModel
    @State private var attempted = false

    var body: some View {
        Group {
            if let issue = model.issues[date] {
                if let category {
                    if let section = issue.sections.first(where: { archiveCategoryName($0.name) == category }) {
                        IssueBody(issue: issue, section: section)
                    } else {
                        ContentUnavailableView("这一期没有该栏目", systemImage: "newspaper")
                    }
                } else {
                    DigestOverview(issue: issue)
                }
            } else if !attempted {
                ProgressView("正在载入这一期")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "这一期暂时打不开",
                    systemImage: "wifi.exclamationmark",
                    description: Text("请检查网络后再试。已保存过的期数可以离线阅读。")
                )
            }
        }
        .navigationTitle(ChineseDate.string(from: date))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.openIssue(date: date)
            attempted = true
        }
    }
}
