import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var reminders: ReminderSettings
    @State private var dataLink: WebLink?

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short)（\(build)）"
    }

    var body: some View {
        Form {
            Section {
                Toggle("每天早上 8:00 提醒", isOn: Binding(
                    get: { reminders.isOn },
                    set: { newValue in
                        Task { await reminders.setOn(newValue) }
                    }
                ))
                Text(reminders.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let nextFire = reminders.nextFire, reminders.isOn {
                    Text("下次提醒：\(nextFire.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "zh_CN"))))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if reminders.needsSystemSettings {
                    Button("打开系统设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("提醒")
            } footer: {
                Text("打开后，手机会在当地时间每天早上 8:00 提示：今天的海外资讯简报已更新。这是本机通知，不经过服务器推送。")
            }

            Section {
                LabeledContent("版本", value: version)
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "com.jincw.overseasdigest")
                Button("查看数据目录") {
                    dataLink = WebLink(url: DigestConfig.baseURL)
                }
            } header: {
                Text("关于")
            } footer: {
                Text("简报从上面的地址读取。成功获取后会保存在这台手机上，没有网络时仍可阅读最近一次打开过的期数。安装包里也带有仓库中的那一期，方便第一次打开。")
            }
        }
        .navigationTitle("设置")
        .sheet(item: $dataLink) { link in
            SafariSheet(url: link.url)
                .ignoresSafeArea()
        }
        .task { await reminders.sync() }
    }
}
