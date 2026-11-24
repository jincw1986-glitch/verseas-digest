import SwiftUI
import AVFoundation
import CoreMotion

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
    @State private var readingRoute: ReadingRoute?
    @State private var finishedReading = false
    @State private var pageTurn = 0
    @State private var mastheadVisible = true
    @AppStorage("overviewOpenedEntries") private var openedEntries = Data()
    @AppStorage("overviewBubbleSound") private var bubbleSound = true

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
                    categoryBubbles
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
                }, onPageOpened: { index in
                    openedEntries = adding(entryKey(section, index), to: openedEntries)
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
        if (0..<section.entryCount).contains(page) {
            openedEntries = adding(entryKey(section, page), to: openedEntries)
        }
        readingRoute = ReadingRoute(section: section.name, page: page)
    }

    private func entryKey(_ section: DigestSection, _ index: Int) -> String {
        "\(issue.date)\u{1f}\(section.name)\u{1f}\(section.bubbleHeadline(at: index))"
    }

    private func entryKeys(in data: Data) -> Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    private func adding(_ key: String, to data: Data) -> Data {
        var entries = entryKeys(in: data)
        guard entries.insert(key).inserted else { return data }
        return (try? JSONEncoder().encode(entries)) ?? data
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

    private var categoryBubbles: some View {
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
            let opened = entryKeys(in: openedEntries)
            BubbleOverview(
                sections: rankedSections,
                soundEnabled: $bubbleSound,
                hasOpened: { section, page in opened.contains(entryKey(section, page)) },
                isFinished: { section in
                    section.entryCount > 0 && (0..<section.entryCount).allSatisfy { opened.contains(entryKey(section, $0)) }
                },
                open: { section, page in open(section, page: page) }
            )
            .id(issue.date)
            .padding(.top, 10)
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

private struct BubbleOverview: View {
    let sections: [DigestSection]
    @Binding var soundEnabled: Bool
    let hasOpened: (DigestSection, Int) -> Bool
    let isFinished: (DigestSection) -> Bool
    let open: (DigestSection, Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var storyDiameter: CGFloat = 68
    @StateObject private var gravity = BubbleGravity()
    @State private var requested: String?
    @State private var displayed: DigestSection?
    @State private var pressed: String?
    @State private var pressure: CGFloat = 0
    @State private var motion: BubbleMotion?
    @State private var transition: Task<Void, Never>?
    @State private var rebound: Task<Void, Never>?
    @State private var railWidth: CGFloat = 0
    @State private var railOffset: CGFloat = 0

    private struct BubbleMotion {
        let started: Date
        let exiting: Bool
        let width: CGFloat
        let offset: CGFloat
        let shifts: [CGFloat]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            cloud
            if let section = displayed {
                rail(section)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.width, initial: true) { _, width in railWidth = width }
            }
        }
        .onChange(of: sections) { _, sections in
            if let current = displayed, let updated = sections.first(where: { $0.name == current.name }) {
                displayed = updated
            }
        }
        .task(id: scenePhase == .active && !reduceMotion) {
            if scenePhase == .active, !reduceMotion { await gravity.track() }
        }
    }

    private var cloud: some View {
        let width = railWidth > 0 ? railWidth : 350
        let area = GravityBubbleBoard.Area.cloud(width: width, diameters: sections.map(categoryDiameter))
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(sections.indices, id: \.self) { index in
                categoryButton(sections[index])
                    .position(gravity.cloudCenters.indices.contains(index)
                              ? gravity.cloudCenters[index] : GravityBubbleBoard.seed(index: index, in: area))
            }
        }
        .frame(height: area.height)
        .clipped()
        .onChange(of: area, initial: true) { _, size in gravity.configureCloud(size) }
    }

    private func categoryDiameter(_ section: DigestSection) -> CGFloat {
        let rating = section.importanceCounts
        return min(112, 61 + CGFloat(rating[.major, default: 0]) * 16
                           + CGFloat(rating[.notable, default: 0]) * 5)
    }

    private func categoryButton(_ section: DigestSection) -> some View {
        let diameter = categoryDiameter(section)
        let completed = isFinished(section)
        return Button {
            select(section)
        } label: {
            bubbleSurface(fill: completed ? section.bubbleColor : .white, selected: requested == section.name) {
                Text(section.bubbleName)
                    .font(.system(diameter > 89 ? .headline : .subheadline, design: .serif, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(completed ? .white : .black)
                    .padding(5)
                    .minimumScaleFactor(0.61)
            }
        }
        .buttonStyle(.plain)
        .frame(width: diameter, height: diameter)
        .scaleEffect(x: pressed == section.name ? 1 + pressure * 0.10 : 1,
                     y: pressed == section.name ? 1 + pressure * 0.19 : 1)
        .zIndex(pressed == section.name ? 1 : 0)
        .accessibilityLabel(section.displayName)
        .accessibilityValue(completed ? "已读完" : "未读完")
        .accessibilityAddTraits(requested == section.name ? .isSelected : [])
        .accessibilityHint("显示该栏的内容气泡")
    }

    private func rail(_ section: DigestSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(section.displayName)
                    .font(.system(.headline, design: .serif, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 6)
                Button {
                    soundEnabled.toggle()
                    if !soundEnabled { JellyBubbleSound.shared.stop() }
                } label: {
                    Image(systemName: soundEnabled ? "speaker.wave.2" : "speaker.slash")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(soundEnabled ? "关闭气泡音效" : "开启气泡音效")
            }
            if section.entryCount > 0 {
                TimelineView(.animation(paused: motion == nil)) { clock in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 6) {
                            ForEach(0..<section.entryCount, id: \.self) { page in
                                let pose = pose(for: page, at: clock.date)
                                storyButton(section, page: page, pose: pose)
                                    .offset(x: pose.x)
                                    .opacity(pose.opacity)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(width: railArea(for: section).width, alignment: .leading)
                        .padding(.vertical, 9)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(key: BubbleRailOffset.self,
                                    value: proxy.frame(in: .named("bubbleRail")).minX)
                            }
                        }
                    }
                    .coordinateSpace(name: "bubbleRail")
                    .scrollIndicators(.hidden)
                    .scrollDisabled(motion != nil)
                    .onPreferenceChange(BubbleRailOffset.self) { railOffset = $0 }
                }
                .id(section.name)
                .padding(.horizontal, -16)
                .clipped()
                .allowsHitTesting(motion == nil)
            }
        }
        .onChange(of: railArea(for: section), initial: true) { _, area in
            gravity.configureRail(area, section: section.name)
        }
    }

    private func storyButton(_ section: DigestSection, page: Int, pose: Pose) -> some View {
        let importance = section.items.indices.contains(page) ? section.items[page].importance : nil
        let opened = hasOpened(section, page)
        let title = section.bubbleHeadline(at: page)
        return Button {
            open(section, page)
        } label: {
            VStack(spacing: 5) {
                bubbleSurface(fill: opened ? (importance?.color ?? section.bubbleColor) : .white, selected: false) {
                    Text(title.count > 9 ? String(title.prefix(8)) + "…" : title)
                        .font(.system(.caption, design: .serif, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.68)
                        .foregroundStyle(opened ? .white : .black)
                        .padding(6)
                }
                .frame(width: storyDiameter, height: storyDiameter)
                .rotationEffect(.degrees(pose.spin))
                .scaleEffect(x: pose.stretch, y: 2 - pose.stretch)
                if !section.items.isEmpty {
                    Text(importance?.label ?? "未评级").font(.caption2)
                }
            }
            .frame(width: storyDiameter)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue([importance?.label, opened ? "已打开" : "未打开"].compactMap { $0 }.joined(separator: "，"))
    }

    private func bubbleSurface<Label: View>(fill: Color, selected: Bool, @ViewBuilder label: () -> Label) -> some View {
        Circle()
            .fill(fill.gradient)
            .overlay { Circle().strokeBorder(selected ? Color.primary : Color.black.opacity(0.14), lineWidth: selected ? 2 : 1) }
            .shadow(color: .black.opacity(0.14), radius: 5, y: 3)
            .overlay { label() }
            .contentShape(Circle())
    }

    private func select(_ section: DigestSection) {
        requested = requested == section.name ? nil : section.name
        if !reduceMotion {
            rebound?.cancel()
            withAnimation(.easeOut(duration: 0.10)) {
                pressed = section.name
                pressure = -1
            }
            rebound = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(100))
                    if let index = sections.firstIndex(where: { $0.name == section.name }) {
                        gravity.nudgeNeighbors(of: index)
                    }
                    withAnimation(.spring(duration: 0.23, bounce: 0.48)) { pressure = 0.92 }
                    try await Task.sleep(for: .milliseconds(230))
                    withAnimation(.spring(duration: 0.22, bounce: 0.32)) { pressure = 0 }
                } catch { return }
            }
        }
        guard transition == nil else { return }
        transition = Task { @MainActor in
            await settle()
            transition = nil
        }
    }

    @MainActor
    private func settle() async {
        while displayed?.name != requested {
            if let section = displayed {
                await roll(section, exiting: true)
                displayed = nil
                motion = nil
                railOffset = 0
            } else if let section = sections.first(where: { $0.name == requested }) {
                gravity.configureRail(railArea(for: section), section: section.name)
                displayed = section
                railOffset = 0
                await roll(section, exiting: false)
                motion = nil
            } else {
                requested = nil
            }
        }
    }

    private struct Pose {
        var x: CGFloat = 0
        var spin = 0.0
        var stretch: CGFloat = 1
        var opacity = 1.0
    }

    private func travel(_ page: Int, in motion: BubbleMotion) -> (x: CGFloat, time: Double) {
        let slot = 16 + CGFloat(page) * (storyDiameter + 6) + motion.offset + shift(at: page, in: motion.shifts)
        let distance = motion.exiting ? min(-6, -slot - storyDiameter - 6) : max(6, motion.width - slot + 6)
        return (distance, max(motion.exiting ? 0.19 : 0.28, Double(abs(distance)) / 430))
    }

    private func pose(for page: Int, at date: Date) -> Pose {
        let shift = shift(at: page, in: motion?.shifts ?? gravity.railShifts)
        let gravitySpin = Double(shift / (storyDiameter * .pi)) * 360
        guard let motion else { return Pose(x: shift, spin: gravitySpin) }
        let elapsed = date.timeIntervalSince(motion.started)
        if reduceMotion {
            let progress = min(1, max(0, elapsed / 0.16))
            return Pose(x: shift, spin: gravitySpin, opacity: motion.exiting ? 1 - progress : progress)
        }
        let (distance, time) = travel(page, in: motion)
        let timeInMotion = elapsed - delay(for: page, in: motion)
        let progress = min(1, max(0, timeInMotion / time))
        let rotation = Double(distance / (storyDiameter * .pi)) * 360
        if motion.exiting {
            return Pose(x: shift + distance * progress, spin: gravitySpin + rotation * progress)
        }
        if timeInMotion <= time {
            return Pose(x: shift + distance * (1 - progress), spin: gravitySpin + rotation * (1 - progress))
        }
        let bounce = min(1, (timeInMotion - time) / 0.22)
        let pulse = sin(bounce * .pi * 2) * (1 - bounce)
        return Pose(x: shift - 7 * pulse, spin: gravitySpin - 8 * pulse, stretch: 1 + 0.13 * pulse)
    }

    private func shift(at page: Int, in shifts: [CGFloat]) -> CGFloat {
        shifts.indices.contains(page) ? shifts[page] : 0
    }

    private func railArea(for section: DigestSection) -> GravityBubbleBoard.Area {
        let viewport = max(railWidth + 32, 250)
        let span = CGFloat(section.entryCount) * storyDiameter + CGFloat(max(0, section.entryCount - 1)) * 6
        let width = span + 32 <= viewport ? viewport : span + 62
        return .init(width: width, height: storyDiameter + 10,
                     diameters: Array(repeating: storyDiameter, count: section.entryCount), horizontal: true)
    }

    private func delay(for page: Int, in motion: BubbleMotion) -> Double {
        if !motion.exiting { return Double(page) * 0.17 }
        let hidden = max(0, Int(-motion.offset / (storyDiameter + 6)))
        return Double(max(0, page - hidden)) * 0.17
    }

    @MainActor
    private func roll(_ section: DigestSection, exiting: Bool) async {
        guard section.entryCount > 0 else { return }
        gravity.railPaused = true
        defer { gravity.railPaused = false }
        let frame = BubbleMotion(started: .now, exiting: exiting, width: max(railWidth + 32, 250),
                                 offset: exiting ? railOffset : 0, shifts: gravity.railShifts)
        motion = frame
        let times = (0..<section.entryCount).map { page in
            (page: page, duration: travel(page, in: frame).time, delay: delay(for: page, in: frame))
        }
        let visible = times.filter { item in
            let x = 16 + CGFloat(item.page) * (storyDiameter + 6) + frame.offset + shift(at: item.page, in: frame.shifts)
            return x < frame.width && x + storyDiameter > 0
        }
        let duration = reduceMotion ? 0.16 : (visible.map { $0.duration + $0.delay }.max() ?? 0.28) + (exiting ? 0 : 0.22)
        await withTaskGroup(of: Void.self) { group in
            for item in visible {
                let time = reduceMotion ? 0.04 : item.delay + (exiting ? min(item.duration * 0.56, 0.20) : item.duration)
                group.addTask { @MainActor in
                    do {
                        try await Task.sleep(for: .seconds(time))
                        if soundEnabled { JellyBubbleSound.shared.play(index: item.page, exiting: exiting) }
                    } catch { return }
                }
            }
            try? await Task.sleep(for: .seconds(duration))
        }
    }
}

private struct BubbleRailOffset: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct GravityBubbleBoard {
    struct Area: Equatable {
        let width: CGFloat
        let height: CGFloat
        let diameters: [CGFloat]
        let horizontal: Bool

        static func cloud(width: CGFloat, diameters: [CGFloat]) -> Self {
            let space = diameters.reduce(0) { $0 + .pi * $1 * $1 / 4 }
            return .init(width: width, height: max(179, space / max(width * 0.65, 1) + 32),
                         diameters: diameters, horizontal: false)
        }
    }

    struct Bubble {
        var center: CGPoint
        let radius: CGFloat
        var velocity = CGVector.zero
    }

    let area: Area
    private(set) var bubbles: [Bubble]

    init(area: Area) {
        self.area = area
        bubbles = area.diameters.enumerated().map { index, size in
            Bubble(center: Self.seed(index: index, in: area), radius: size / 2)
        }
        if !area.horizontal {
            arrangeInCenter()
        }
    }

    static func seed(index: Int, in area: Area) -> CGPoint {
        if area.horizontal {
            let diameter = area.diameters[index]
            return CGPoint(x: 16 + CGFloat(index) * (diameter + 6) + diameter / 2, y: area.height / 2)
        }
        let columns = max(1, Int(area.width / 86))
        let rows = max(1, (area.diameters.count + columns - 1) / columns)
        return CGPoint(x: (CGFloat(index % columns) + 0.5) * area.width / CGFloat(columns),
                       y: (CGFloat(index / columns) + 0.5) * area.height / CGFloat(rows))
    }

    private mutating func arrangeInCenter() {
        var placed: [Bubble] = []
        for index in bubbles.indices {
            let radius = bubbles[index].radius
            var nearest = CGFloat.greatestFiniteMagnitude
            let center = bubbles[index].center
            for y in stride(from: radius + 2, through: area.height - radius - 2, by: 5) {
                for x in stride(from: radius + 2, through: area.width - radius - 2, by: 5) {
                    let distance = hypot(x - center.x, y - center.y)
                    if distance < nearest, placed.allSatisfy({ hypot($0.center.x - x, $0.center.y - y) >= $0.radius + radius }) {
                        nearest = distance
                        bubbles[index].center = CGPoint(x: x, y: y)
                    }
                }
            }
            placed.append(bubbles[index])
        }
        for _ in 0..<12 { step(x: 0, y: 0, delta: 0) }
    }

    mutating func nudgeNeighbors(of index: Int) {
        guard bubbles.indices.contains(index) else { return }
        let source = bubbles[index]
        for other in bubbles.indices where other != index {
            let dx = bubbles[other].center.x - source.center.x
            let dy = bubbles[other].center.y - source.center.y
            let distance = hypot(dx, dy)
            let gap = distance - source.radius - bubbles[other].radius
            if distance > 0, gap < 24 {
                let strength = max(75, 175 - gap * 4)
                bubbles[other].velocity.dx += dx / distance * strength
                bubbles[other].velocity.dy += dy / distance * strength
            }
        }
    }

    mutating func step(x: CGFloat, y: CGFloat, delta: CGFloat) {
        let damping: CGFloat = area.horizontal ? 0.958 : 0.973
        for index in bubbles.indices {
            bubbles[index].velocity.dx = min(580, max(-580, (bubbles[index].velocity.dx + x * delta) * damping))
            bubbles[index].velocity.dy = area.horizontal ? 0 : min(580, max(-580, (bubbles[index].velocity.dy + y * delta) * damping))
            bubbles[index].center.x += bubbles[index].velocity.dx * delta
            bubbles[index].center.y += bubbles[index].velocity.dy * delta
            constrain(index)
        }
        for _ in 0..<3 {
            for first in bubbles.indices {
                for second in (first + 1)..<bubbles.count { collide(first, second) }
            }
            for index in bubbles.indices { constrain(index) }
        }
    }

    private mutating func constrain(_ index: Int) {
        let radius = bubbles[index].radius + 2
        let right = max(radius, area.width - radius)
        if bubbles[index].center.x < radius {
            bubbles[index].center.x = radius
            bubbles[index].velocity.dx = abs(bubbles[index].velocity.dx) * 0.43
        } else if bubbles[index].center.x > right {
            bubbles[index].center.x = right
            bubbles[index].velocity.dx = -abs(bubbles[index].velocity.dx) * 0.43
        }
        if area.horizontal {
            bubbles[index].center.y = area.height / 2
            return
        }
        let bottom = max(radius, area.height - radius)
        if bubbles[index].center.y < radius {
            bubbles[index].center.y = radius
            bubbles[index].velocity.dy = abs(bubbles[index].velocity.dy) * 0.43
        } else if bubbles[index].center.y > bottom {
            bubbles[index].center.y = bottom
            bubbles[index].velocity.dy = -abs(bubbles[index].velocity.dy) * 0.43
        }
    }

    private mutating func collide(_ first: Int, _ second: Int) {
        let a = bubbles[first], b = bubbles[second]
        let dx = b.center.x - a.center.x, dy = b.center.y - a.center.y
        let distance = hypot(dx, dy)
        let overlap = a.radius + b.radius - distance
        guard overlap > 0 else { return }
        let nx = distance > 0.01 ? dx / distance : 1
        let ny = distance > 0.01 ? dy / distance : 0
        let correction = overlap * 0.47
        bubbles[first].center.x -= nx * correction
        bubbles[first].center.y -= ny * correction
        bubbles[second].center.x += nx * correction
        bubbles[second].center.y += ny * correction
        let closing = (b.velocity.dx - a.velocity.dx) * nx + (b.velocity.dy - a.velocity.dy) * ny
        if closing < 0 {
            let impulse = -closing * 0.72
            bubbles[first].velocity.dx -= nx * impulse
            bubbles[first].velocity.dy -= ny * impulse
            bubbles[second].velocity.dx += nx * impulse
            bubbles[second].velocity.dy += ny * impulse
        }
    }
}

@MainActor
private final class BubbleGravity: ObservableObject {
    @Published private(set) var cloudCenters: [CGPoint] = []
    @Published private(set) var railShifts: [CGFloat] = []

    var railPaused = false
    private let motion = CMMotionManager()
    private var cloud: GravityBubbleBoard?
    private var rail: GravityBubbleBoard?
    private var currentSection: String?

    func configureCloud(_ area: GravityBubbleBoard.Area) {
        guard cloud?.area != area else { return }
        let board = GravityBubbleBoard(area: area)
        cloud = board
        cloudCenters = board.bubbles.map(\.center)
    }

    func configureRail(_ area: GravityBubbleBoard.Area, section: String) {
        guard rail?.area != area || currentSection != section else { return }
        rail = GravityBubbleBoard(area: area)
        currentSection = section
        railShifts = Array(repeating: 0, count: area.diameters.count)
    }

    func nudgeNeighbors(of index: Int) { cloud?.nudgeNeighbors(of: index) }

    func track() async {
        let hasMotion = motion.isDeviceMotionAvailable
        if hasMotion {
            motion.deviceMotionUpdateInterval = 1.0 / 50.0
            motion.startDeviceMotionUpdates()
        }
        defer { if hasMotion { motion.stopDeviceMotionUpdates() } }
        let clock = ContinuousClock()
        var last = clock.now
        while !Task.isCancelled {
            let now = clock.now
            let elapsed = last.duration(to: now).components
            let delta = min(0.034, CGFloat(elapsed.seconds) + CGFloat(elapsed.attoseconds) / 1e18)
            last = now
            let gravity = screenGravity()
            tick(x: gravity.dx, y: gravity.dy, delta: delta)
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
        }
    }

    private func screenGravity() -> CGVector {
        guard let sample = motion.deviceMotion?.gravity else { return .zero }
        let x = CGFloat(sample.x), y = CGFloat(sample.y)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        switch scene?.interfaceOrientation {
        case .landscapeLeft: return CGVector(dx: -y, dy: -x)
        case .landscapeRight: return CGVector(dx: y, dy: x)
        case .portraitUpsideDown: return CGVector(dx: -x, dy: y)
        default: return CGVector(dx: x, dy: -y)
        }
    }

    private func tick(x: CGFloat, y: CGFloat, delta: CGFloat) {
        cloud?.step(x: x * 620, y: y * 620, delta: delta)
        if let positions = cloud?.bubbles.map(\.center),
           zip(positions, cloudCenters).contains(where: { hypot($0.0.x - $0.1.x, $0.0.y - $0.1.y) > 0.2 }) {
            cloudCenters = positions
        }
        guard !railPaused, var board = rail else { return }
        board.step(x: x * 680, y: 0, delta: delta)
        rail = board
        let shifts = board.bubbles.enumerated().map { index, bubble in
            bubble.center.x - GravityBubbleBoard.seed(index: index, in: board.area).x
        }
        if zip(shifts, railShifts).contains(where: { abs($0.0 - $0.1) > 0.2 }) { railShifts = shifts }
    }
}

@MainActor
private final class JellyBubbleSound {
    static let shared = JellyBubbleSound()
    private let cues: [TimeInterval] = [0.045, 0.265, 0.385, 0.565, 0.765, 0.965, 1.165, 1.285, 1.505, 1.645]
    private var players: [AVAudioPlayer] = []

    func play(index: Int, exiting: Bool) {
        guard let data = NSDataAsset(name: "JellyBubbleSound")?.data,
              let player = try? AVAudioPlayer(data: data) else { return }
        let cue = cues[(index + (exiting ? 5 : 0)) % cues.count]
        player.currentTime = cue
        player.volume = exiting ? 0.36 : 0.52
        players.append(player)
        player.play()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(110))
            player.stop()
            players.removeAll { $0 === player }
        }
    }

    func stop() {
        players.forEach { $0.stop() }
        players.removeAll()
    }
}

private extension DigestSection {
    var bubbleName: String {
        switch name {
        case "国际政治与时事": "国际政治"
        case "经济与市场": "经济市场"
        case "科技与人工智能": "科技 AI"
        case "社会与荒诞", "社会资讯": "社会"
        case "科学与体育": "科学体育"
        case "影视与明星": "影视"
        case "书籍与作家": "书籍作家"
        default: displayName
        }
    }

    var bubbleColor: Color {
        switch name {
        case "国际政治与时事": Color(red: 0.32, green: 0.26, blue: 0.18)
        case "经济与市场": Color(red: 0.43, green: 0.40, blue: 0.13)
        case "科技与人工智能": Color(red: 0.21, green: 0.37, blue: 0.29)
        case "社会与荒诞", "社会资讯": Color(red: 0.49, green: 0.20, blue: 0.16)
        case "科学与体育": Color(red: 0.22, green: 0.37, blue: 0.43)
        case "影视与明星": Color(red: 0.42, green: 0.22, blue: 0.49)
        case "书籍与作家": Color(red: 0.65, green: 0.27, blue: 0.23)
        case "美女与野兽": Color(red: 0.36, green: 0.45, blue: 0.23)
        case "天涯海角": Color(red: 0.12, green: 0.46, blue: 0.42)
        case "维基漫游": Color(red: 0.35, green: 0.32, blue: 0.58)
        default: Color(red: 0.46, green: 0.32, blue: 0.23)
        }
    }

    func bubbleHeadline(at index: Int) -> String {
        if items.indices.contains(index) { return items[index].headline }
        if jokes.indices.contains(index) { return jokes[index].translation ?? jokes[index].text }
        if gallery.indices.contains(index) { return gallery[index].caption }
        return place?.name ?? wiki?.title ?? photo?.title ?? displayName
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
