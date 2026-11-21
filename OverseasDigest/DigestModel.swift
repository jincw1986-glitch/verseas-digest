import Combine
import Foundation

@MainActor
final class DigestModel: ObservableObject {
    @Published private(set) var index: IssueIndex?
    @Published private(set) var issues: [String: DigestIssue] = [:]
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
