import SwiftUI

struct IssueBody: View {
    let issue: DigestIssue
    @EnvironmentObject private var model: DigestModel
    @State private var selectedSection = ""
    @State private var showDirectory = false
    @State private var sheet: PresentedSheet?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        masthead
                        if let banner = model.banner {
                            Text(banner)
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        ForEach(issue.sections) { section in
                            sectionView(section)
                                .id(section.name)
                        }
                        Text("新闻摘要据公开报道整理，点开来源可阅读原文。笑话是 X 上的原帖，点作者名字可打开帖子。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
            }
            .refreshable { await model.refresh() }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showDirectory = true
                    } label: {
                        Label("栏目", systemImage: "line.3.horizontal")
                    }
                }
            }
            .overlay {
                if showDirectory {
                    sectionDirectory(proxy: proxy)
                }
            }
            .animation(.easeInOut(duration: 0.28), value: showDirectory)
        }
        .sheet(item: $sheet) { presented in
            SheetContent(presented: presented)
        }
    }

    private func sectionDirectory(proxy: ScrollViewProxy) -> some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { showDirectory = false }
                .accessibilityLabel("关闭栏目目录")
                .accessibilityAddTraits(.isButton)
            VStack(alignment: .leading, spacing: 0) {
                Text("栏目目录")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(issue.sections) { section in
                            Button {
                                selectedSection = section.name
                                showDirectory = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        proxy.scrollTo(section.name, anchor: .top)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(section.name)
                                        .font(.body.weight(activeSection == section.name ? .semibold : .regular))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 8)
                                    Text("\(section.entryCount)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(activeSection == section.name ? Color.white : Color.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(
                                            activeSection == section.name ? Color.accentColor : Color.secondary.opacity(0.15),
                                            in: Capsule()
                                        )
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 48)
                                .background(
                                    activeSection == section.name ? Color.accentColor.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("跳转到该栏目")
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .frame(maxWidth: 320, maxHeight: .infinity, alignment: .top)
            .frame(width: 300)
            .background(.regularMaterial)
            .ignoresSafeArea(edges: .bottom)
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }

    private var activeSection: String {
        if selectedSection.isEmpty {
            return issue.sections.first?.name ?? ""
        }
        return selectedSection
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("海外资讯简报")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(ChineseDate.string(from: issue.date))
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(issue.title)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    private func sectionView(_ section: DigestSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.name)
                    .font(.title2.weight(.bold))
                Spacer(minLength: 8)
                Text("\(section.entryCount)则")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            if section.name == "笑话" {
                ForEach(section.jokes) { joke in
                    JokeCard(joke: joke) { url in
                        sheet = .web(WebLink(url: url))
                    }
                }
            } else {
                ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                    itemCard(item, sectionName: section.name)
                }
            }
        }
    }

    private func itemCard(_ item: DigestItem, sectionName: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                ItemDetailView(sectionName: sectionName, item: item)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    if let picture = item.image {
                        DigestPhoto(picture: picture)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text(picture.credit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(sectionName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(item.headline)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.summary)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.plain)
            SourceButtons(sources: item.sources) { url in
                sheet = .web(WebLink(url: url))
            }
            DisclosureGroup("名词解释") {
                GlossaryBlock(entries: item.glossary) { entry in
                    sheet = .glossary(entry)
                }
                .padding(.top, 8)
            }
            .font(.body.weight(.semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
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
                if let picture = item.image {
                    DigestPhoto(picture: picture)
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

    var body: some View {
        Group {
            if let index = model.index, !index.issues.isEmpty {
                List(index.issues) { entry in
                    NavigationLink(value: entry.date) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(ChineseDate.string(from: entry.date))
                                    .font(.headline)
                                if entry.date == index.issues.first?.date {
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
            } else {
                ContentUnavailableView(
                    "还没有往期",
                    systemImage: "books.vertical",
                    description: Text("下拉可重新获取目录。")
                )
            }
        }
        .navigationTitle("往期")
        .navigationDestination(for: String.self) { date in
            ArchivedIssueView(date: date)
        }
        .refreshable { await model.refresh() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                RefreshButton()
            }
        }
    }
}

struct ArchivedIssueView: View {
    let date: String
    @EnvironmentObject private var model: DigestModel
    @State private var attempted = false

    var body: some View {
        Group {
            if let issue = model.issues[date] {
                IssueBody(issue: issue)
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
