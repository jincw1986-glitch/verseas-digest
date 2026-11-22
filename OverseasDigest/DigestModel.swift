import Combine
import Foundation

@MainActor
final class DigestModel: ObservableObject {
    @Published private(set) var index: IssueIndex?
    @Published private(set) var issues: [String: DigestIssue] = [:]
    @Published private var archivedSectionNames: [IndexEntry: [String]] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var banner: String?

    private let repository: DigestRepository

    init(repository: DigestRepository = .shared) {
        self.repository = repository
        index = repository.loadIndex()
        if let latest = index?.issues.first, let issue = repository.loadIssue(latest) {
            issues[latest.date] = issue
        }
    }

    var latestIssue: DigestIssue? {
        guard let date = index?.issues.first?.date else { return nil }
        return issues[date]
    }

    func refresh() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fetched = try await repository.fetchIndex()
            index = fetched
            var wanted = Set(issues.keys)
            if let latest = fetched.issues.first?.date {
                wanted.insert(latest)
            }
            for entry in fetched.issues where wanted.contains(entry.date) {
                do {
                    issues[entry.date] = try await repository.fetchIssue(entry)
                } catch {
                    if issues[entry.date] == nil, let local = repository.loadIssue(entry) {
                        issues[entry.date] = local
                    }
                }
            }
            if let latest = fetched.issues.first?.date, issues[latest] == nil {
                banner = "最新一期暂时无法打开，请下拉重试。"
            } else {
                banner = nil
            }
        } catch {
            if index == nil {
                index = repository.loadIndex()
            }
            if let index {
                for entry in index.issues where issues[entry.date] == nil {
                    if let local = repository.loadIssue(entry) {
                        issues[entry.date] = local
                    }
                }
            }
            banner = issues.isEmpty
                ? "无法获取简报，请检查网络后下拉重试。"
                : "暂时连不上线上数据，正在显示已保存在这台手机上的简报。"
        }
    }

    func reloadFromDisk() {
        repository.clearPictureMemory()
        archivedSectionNames.removeAll()
        let loaded = repository.loadIndex()
        index = loaded
        var next: [String: DigestIssue] = [:]
        if let loaded {
            for entry in loaded.issues {
                if let issue = repository.loadIssue(entry) {
                    next[entry.date] = issue
                }
            }
        }
        issues = next
    }

    func sectionNames(in entry: IndexEntry) -> [String]? {
        issues[entry.date]?.sections.map(\.name) ?? archivedSectionNames[entry]
    }

    func loadArchiveSections(_ entries: [IndexEntry]) async {
        var uncached: [IndexEntry] = []
        for entry in entries where sectionNames(in: entry) == nil {
            if let local = repository.loadIssue(entry) {
                archivedSectionNames[entry] = local.sections.map(\.name)
            } else {
                uncached.append(entry)
            }
        }

        // Fetch in small batches so a large archive doesn't start a request for every issue at once.
        let repository = repository
        for start in stride(from: 0, to: uncached.count, by: 4) {
            guard !Task.isCancelled else { return }
            await withTaskGroup(of: (IndexEntry, [String]?).self) { group in
                for entry in uncached[start..<min(start + 4, uncached.count)] {
                    group.addTask {
                        let issue = try? await repository.fetchIssue(entry)
                        return (entry, issue?.sections.map(\.name))
                    }
                }
                for await (entry, names) in group {
                    if !Task.isCancelled, let names {
                        archivedSectionNames[entry] = names
                    }
                }
            }
        }
    }

    func openIssue(date: String) async {
        guard let entry = index?.issues.first(where: { $0.date == date }) else { return }
        if issues[date] == nil, let local = repository.loadIssue(entry) {
            issues[date] = local
        }
        let fresh: DigestIssue?
        do {
            fresh = try await repository.fetchIssue(entry)
        } catch {
            fresh = nil
        }
        if let fresh {
            issues[date] = fresh
        }
    }
}
