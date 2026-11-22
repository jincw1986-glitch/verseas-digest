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
    @AppStorage(DigestAppearance.storageKey) private var appearance: DigestAppearance = .system
    @State private var showsDirectory = false
    @State private var directorySelection: String?

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
                if showsRefresh, let banner = model.banner {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let section = issue.sections.first(where: { $0.photo != nil }), let photo = section.photo {
                    dailyPhoto(photo, section: section)
                }
                if !issue.readingSections.isEmpty {
                    categoryList
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .background(paper.ignoresSafeArea())
        .accessibilityHidden(showsDirectory)
        .overlay {
            if showsDirectory {
                directory
            }
        }
        .navigationDestination(item: $directorySelection) { name in
            if let section = issue.readingSections.first(where: { $0.name == name }) {
                IssueBody(issue: issue, section: section)
            }
        }
        .toolbarBackground(paper, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsRefresh {
                HStack(spacing: 4) {
                    publicationName
                    Spacer(minLength: 0)
                    appearanceButton
                    RefreshButton()
                        .frame(minWidth: 44, minHeight: 44)
                }
                editionDate.frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        publicationName
                        Spacer(minLength: 0)
                        editionDate.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        publicationName
                        editionDate
                    }
                }
            }
            Rectangle()
                .fill(.primary)
                .frame(height: 2)
            Divider().padding(.top, -5)
        }
    }

    private var publicationName: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { showsDirectory = true }
        } label: {
            Text("猫头鹰")
                .font(.system(.largeTitle, design: .serif, weight: .heavy))
                .frame(minHeight: 44)
                .fixedSize()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                                    directorySelection = section.name
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(section.name)
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
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isNight ? "切换到白天模式" : "切换到夜间模式")
    }

    private func dailyPhoto(_ photo: PhotoOfDay, section: DigestSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.name)
                .font(.system(.title2, design: .serif, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            NavigationLink {
                IssueBody(issue: issue, section: section)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    Color.clear.aspectRatio(3.0 / 2.0, contentMode: .fit)
                        .overlay {
                            DigestPhoto(picture: photo.image, fillsFrame: true)
                        }
                        .clipped()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    HStack(spacing: 8) {
                        Text(photo.title)
                            .font(.system(.title2, design: .serif, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
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
    }

    private var categoryList: some View {
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
            ForEach(rankedSections) { section in
                OverviewCategoryRow(issue: issue, section: section)
                Divider()
            }
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

private struct OverviewCategoryRow: View {
    let issue: DigestIssue
    let section: DigestSection

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
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                IssueBody(issue: issue, section: section)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(section.name).font(.system(.headline, design: .serif))
                        Spacer(minLength: 0)
                        Text("\(section.entryCount)则")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    if !section.items.isEmpty {
                        importanceBreakdown
                    }
                }
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let index = headlineIndex {
                NavigationLink {
                    IssueBody(issue: issue, section: section, page: index)
                } label: {
                    Text(section.items[index].headline)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var importanceBreakdown: some View {
        let counts = counts
        let unrated = section.items.count - counts.reduce(0, +)
        if unrated == section.items.count {
            Text("未评级").font(.caption).foregroundStyle(.secondary)
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
            .accessibilityHidden(true)
            let ratings = zip(NewsImportance.allCases, counts).map { level, count in "\(level.label) \(count)" }
            let labels = unrated > 0 ? ratings + ["未评级 \(unrated)"] : ratings
            Text(labels.joined(separator: " · "))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
