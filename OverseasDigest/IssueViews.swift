import SwiftUI

struct IssueBody: View {
    let issue: DigestIssue
    @EnvironmentObject private var model: DigestModel
    @State private var selectedSection = ""
    @State private var sheet: PresentedSheet?

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                sectionChips(proxy: proxy)
                Divider()
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
                        Text("摘要据公开报道整理，点开来源可阅读原文。名词解释是为阅读准备的背景，不是新闻原文。")
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
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(item: $sheet) { presented in
            SheetContent(presented: presented)
        }
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

    private func sectionChips(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(issue.sections) { section in
                    Button {
                        selectedSection = section.name
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(section.name, anchor: .top)
                        }
                    } label: {
                        Text(section.name)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .foregroundStyle(activeSection == section.name ? Color.white : Color.primary)
                            .background(
                                activeSection == section.name ? Color.accentColor : Color.secondary.opacity(0.15),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(activeSection == section.name ? .isSelected : AccessibilityTraits())
                    .accessibilityHint("跳转到该栏目")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func sectionView(_ section: DigestSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.name)
                    .font(.title2.weight(.bold))
                Spacer(minLength: 8)
                Text("\(section.items.count)则")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                itemCard(item, sectionName: section.name)
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
