import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: DigestModel

    var body: some View {
        Group {
            if let issue = model.latestIssue {
                IssueBody(issue: issue)
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
