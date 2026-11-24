import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: DigestModel

    var body: some View {
        Group {
            if let issue = model.latestIssue {
                DigestOverview(issue: issue, showsRefresh: true)
                    .toolbar(.hidden, for: .navigationBar)
                    .refreshable { await model.refresh() }
            } else if model.isRefreshing {
                ProgressView("正在获取简报")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "还没有简报",
                    systemImage: "newspaper",
                    description: Text(model.banner ?? "下拉可获取今天的海外资讯简报。")
                )
                .refreshable { await model.refresh() }
            }
        }
        .navigationTitle("今日")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                RefreshButton()
            }
        }
    }
}

struct DigestOverview: View {
    let issue: DigestIssue
    var showsRefresh = false

    @EnvironmentObject private var model: DigestModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(DigestAppearance.storageKey) private var appearance: DigestAppearance = .system
    @State private var showsDirectory = false
    @State private var readingRoute: ReadingRoute?
    @State private var finishedReading = false
    @State private var pageTurn = 0
    @State private var mastheadVisible = true

    private struct ReadingRoute: Hashable {
        let section: String
        let page: Int
    }

    private var paper: Color {
        colorScheme == .dark ? Color(red: 0.08, green: 0.10, blue: 0.13)
            : Color(red: 0.97, green: 0.95, blue: 0.91)
    }

    private var hasRatings: Bool {
        issue.readingSections.contains { $0.items.contains { $0.importance != nil } }
    }

    private var rankedSections: [DigestSection] {
        let ranked = issue.readingSections.enumerated().map { index, section in
            let counts = section.importanceCounts
            return (
                section: section,
                priority: (counts[.major, default: 0], counts[.notable, default: 0]),
                hasRating: !counts.isEmpty,
                index: index
            )
        }
        return ranked.sorted { first, second in
            if first.priority != second.priority { return first.priority > second.priority }
            if first.hasRating != second.hasRating { return first.hasRating }
            return first.index < second.index
        }.map { $0.section }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                masthead
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: MastheadVisibility.self,
                                                   value: geometry.frame(in: .named("digestOverview")).maxY > 30)
                        }
                    }
                if showsRefresh, let banner = model.banner {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let section = issue.sections.first(where: { $0.photo != nil }), let photo = section.photo {
                    dailyPhoto(photo, section: section)
                }
                if !issue.readingSections.isEmpty {
                    categoryMosaic
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .coordinateSpace(name: "digestOverview")
        .onPreferenceChange(MastheadVisibility.self) { mastheadVisible = $0 }
        .background(paper.ignoresSafeArea())
        .accessibilityHidden(showsDirectory)
        .overlay {
            if showsDirectory {
                directory
            }
        }
        .navigationDestination(item: $readingRoute) { route in
            if let section = issue.sections.first(where: { $0.name == route.section }) {
                IssueBody(issue: issue, section: section, page: route.page, onReading: {
                    if readingRoute == route { finishedReading = true }
                })
            }
        }
        .onChange(of: readingRoute) { _, route in
            if route == nil, finishedReading {
                finishedReading = false
                pageTurn += 1
            }
        }
        .toolbarBackground(paper, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

    private var masthead: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .bottomLeading) {
                VStack(alignment: .trailing, spacing: 0) {
                    if showsRefresh {
                        HStack(spacing: 0) {
                            appearanceButton
                            RefreshButton()
                                .frame(width: 44, height: 44, alignment: .top)
                        }
                    }
                    editionDate
                        .multilineTextAlignment(.trailing)
                        .padding(.leading, 60)
                    Spacer(minLength: 4)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 6)
                .frame(minHeight: 88, alignment: .topTrailing)

                publicationName
            }
            .padding(.bottom, -3)
            .zIndex(1)
            Rectangle().fill(.primary).frame(height: 2)
            Divider()
        }
    }

    private var publicationName: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { showsDirectory = true }
        } label: {
            MastheadOwl(turn: mastheadVisible ? pageTurn : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("猫头鹰")
        .accessibilityHint("打开栏目目录")
        .disabled(issue.readingSections.isEmpty)
    }

    private var directory: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Button(action: closeDirectory) {
                    Color.black.opacity(0.38)
                }
                .buttonStyle(.plain)
                .ignoresSafeArea()
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text("栏目目录")
                            .font(.system(.title2, design: .serif, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 4)
                        Button("关闭", action: closeDirectory)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(issue.readingSections) { section in
                                Button {
                                    closeDirectory()
                                    open(section)
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(section.displayName)
                                            .font(.body)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 4)
                                        Text("\(section.entryCount)则")
                                            .font(.subheadline.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .fixedSize()
                                    }
                                    .padding(.vertical, 6)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .frame(width: min(geometry.size.width * 0.83, 320), height: geometry.size.height)
                .background(paper)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape, closeDirectory)
            }
        }
        .transition(.opacity)
    }

    private func closeDirectory() {
        withAnimation(.easeInOut(duration: 0.25)) { showsDirectory = false }
    }

    private func open(_ section: DigestSection, page: Int = 0) {
        finishedReading = false
        readingRoute = ReadingRoute(section: section.name, page: page)
    }

    private var editionDate: some View {
        Text(ChineseDate.string(from: issue.date))
            .font(.system(.subheadline, design: .serif, weight: .semibold))
    }

    private var appearanceButton: some View {
        let isNight = colorScheme == .dark
        return Button {
            appearance = isNight ? .day : .night
        } label: {
            Image(systemName: isNight ? "sun.max" : "moon")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(height: 20)
                .frame(width: 44, height: 44, alignment: .top)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isNight ? "切换到白天模式" : "切换到夜间模式")
    }

    private func dailyPhoto(_ photo: PhotoOfDay, section: DigestSection) -> some View {
        Button {
            open(section)
        } label: {
            ZStack(alignment: .bottomLeading) {
                Color.clear.aspectRatio(3.0 / 2.0, contentMode: .fit)
                    .overlay {
                        DigestPhoto(picture: photo.image, fillsFrame: true)
                    }
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.displayName)
                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                    HStack(spacing: 8) {
                        Text(photo.title)
                            .font(.system(.title2, design: .serif, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .multilineTextAlignment(.leading)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.top, 38)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.62), location: 0.42),
                                .init(color: .black.opacity(0.88), location: 1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("阅读图片背后的故事")
    }

    private var categoryMosaic: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    categoryTitle
                    Spacer(minLength: 12)
                    legend
                }
                VStack(alignment: .leading, spacing: 8) {
                    categoryTitle
                    legend
                }
            }
            .padding(.vertical, 12)
            Rectangle().fill(.primary).frame(height: 1)
            mosaicTiles.padding(.top, 10)
        }
    }

    @ViewBuilder
    private var mosaicTiles: some View {
        let sections = rankedSections
        if typeSize.isAccessibilitySize || sections.count < 3 {
            VStack(spacing: 10) {
                ForEach(sections.indices, id: \.self) { index in
                    tile(sections[index], index: index)
                }
            }
        } else {
            HStack(spacing: 10) {
                tile(sections[0], index: 0)
                VStack(spacing: 10) {
                    tile(sections[1], index: 1)
                    tile(sections[2], index: 2)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ForEach(sections.indices.dropFirst(3), id: \.self) { index in
                    tile(sections[index], index: index)
                }
            }
            .padding(.top, 10)
        }
    }

    private func tile(_ section: DigestSection, index: Int) -> some View {
        OverviewCategoryTile(section: section, position: index) { page in
            open(section, page: page)
        }
    }

    private var categoryTitle: some View {
        Text("栏目一览")
            .font(.system(.title2, design: .serif, weight: .bold))
            .accessibilityAddTraits(.isHeader)
            .fixedSize()
    }

    @ViewBuilder
    private var legend: some View {
        if hasRatings {
            HStack(spacing: 10) {
                ForEach(NewsImportance.allCases, id: \.self) { level in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(level.color)
                            .frame(width: 9, height: 9)
                        Text(level.label).font(.caption)
                    }
                }
            }
            .fixedSize()
        }
    }
}

private struct MastheadVisibility: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct OverviewCategoryTile: View {
    let section: DigestSection
    let position: Int
    let open: (Int) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isLead: Bool { position == 0 }

    private var ink: Color { isLead || colorScheme == .dark ? .white : Color(red: 0.13, green: 0.11, blue: 0.12) }

    private var surface: Color {
        if isLead { return Color(red: 0.36, green: 0.15, blue: 0.23) }
        let tints: [Color] = [
            Color(red: 0.91, green: 0.75, blue: 0.55),
            Color(red: 0.68, green: 0.76, blue: 0.82),
            Color(red: 0.86, green: 0.77, blue: 0.58),
            Color(red: 0.76, green: 0.76, blue: 0.61)
        ]
        return tints[(position - 1) % tints.count].opacity(colorScheme == .dark ? 0.21 : 0.55)
    }

    private var counts: [Int] {
        let totals = section.importanceCounts
        return NewsImportance.allCases.map { totals[$0, default: 0] }
    }

    private var headlineIndex: Int? {
        guard let first = section.items.indices.first else { return nil }
        let highestRank = section.items.compactMap { $0.importance?.rank }.max()
        guard let highestRank else { return first }
        return section.items.firstIndex { $0.importance?.rank == highestRank }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                open(0)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(section.displayName)
                            .font(.system(isLead ? .title2 : .headline, design: .serif, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    if isLead, let major = section.importanceCounts[.major], major > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text("\(major)")
                                .font(.system(.largeTitle, design: .serif, weight: .heavy).monospacedDigit())
                            Text("重大").font(.system(.headline, design: .serif))
                        }
                        .accessibilityHidden(true)
                    }
                    if !section.items.isEmpty {
                        importanceBreakdown
                    } else {
                        Text("\(section.entryCount)则")
                            .font(.subheadline.monospacedDigit())
                    }
                }
                .frame(maxWidth: .infinity, minHeight: isLead ? 44 : 94, alignment: .topLeading)
                .padding(isLead ? 0 : 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isLead, let index = headlineIndex {
                Rectangle().fill(ink.opacity(0.35)).frame(height: 1)
                Button {
                    open(index)
                } label: {
                    HStack(spacing: 6) {
                        Text(section.items[index].headline)
                            .font(.system(.headline, design: .serif))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44, alignment: .topLeading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(ink)
        .padding(isLead ? 14 : 0)
        .frame(maxWidth: .infinity, minHeight: isLead ? 242 : 116, alignment: .topLeading)
        .background {
            LinearGradient(colors: [surface, surface.opacity(0.80)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay {
                    GeometryReader { geometry in
                        Image("OverviewPaper")
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .trailing)
                            .clipped()
                    }
                    .opacity(isLead ? 0.23 : 0.18)
                    .blendMode(isLead || colorScheme == .dark ? .softLight : .multiply)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .compositingGroup()
        }
    }

    @ViewBuilder
    private var importanceBreakdown: some View {
        let counts = counts
        let unrated = section.items.count - counts.reduce(0, +)
        if unrated == section.items.count {
            Text("未评级").font(.caption)
        } else {
            let shares = counts + [unrated]
            let colors = NewsImportance.allCases.map(\.color) + [Color.secondary.opacity(0.25)]
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(shares.indices, id: \.self) { index in
                        if shares[index] > 0 {
                            colors[index]
                                .frame(width: geometry.size.width * CGFloat(shares[index]) / CGFloat(section.items.count))
                        }
                    }
                }
            }
            .frame(height: 7)
            .clipShape(Capsule())
            .accessibilityHidden(true)
            let ratings = zip(NewsImportance.allCases, counts).map { level, count in "\(level.label) \(count)" }
            let labels = unrated > 0 ? ratings + ["未评级 \(unrated)"] : ratings
            Text(labels.joined(separator: " · "))
                .font(.caption.monospacedDigit())
        }
    }
}

private struct MastheadOwl: View {
    let turn: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle = 0.0
    @State private var opacity = 0.0
    @State private var playedTurn = 0

    var body: some View {
        ZStack {
            owl
            owl
                .mask {
                    Path { path in
                        path.move(to: CGPoint(x: 34.6, y: 37.0))
                        path.addLine(to: CGPoint(x: 48.0, y: 34.7))
                        path.addLine(to: CGPoint(x: 46.6, y: 49.8))
                        path.addLine(to: CGPoint(x: 34.6, y: 53.9))
                        path.closeSubpath()
                    }
                    .fill(.white)
                }
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: UnitPoint(x: 0.494, y: 0.65))
                .brightness(0.12)
                .opacity(opacity)
        }
        .frame(width: 52, height: 64)
        .offset(y: 2)
        .accessibilityHidden(true)
        .task(id: turn) {
            guard turn > playedTurn else { return }
            do {
                try await Task.sleep(for: .milliseconds(240))
                playedTurn = turn
                angle = 0
                opacity = reduceMotion ? 0 : 1
                withAnimation(.easeInOut(duration: 0.25)) {
                    if reduceMotion { opacity = 1 } else { angle = -155 }
                }
                try await Task.sleep(for: .milliseconds(250))
                withAnimation(.easeOut(duration: 0.10)) { opacity = 0 }
            } catch {
                opacity = 0
            }
        }
    }

    private var owl: some View {
        Image("MastheadOwl").resizable().frame(width: 72, height: 72)
    }
}
