import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: DigestModel
    @EnvironmentObject private var reminders: ReminderSettings
    @StateObject private var backup = BackupSession()
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
                Button("导出备份") {
                    Task { await backup.export() }
                }
                .disabled(backup.isWorking)
                Button("导入备份") {
                    backup.showImporter = true
                }
                .disabled(backup.isWorking)
                if backup.isWorking {
                    if backup.total > 0 {
                        ProgressView(value: Double(backup.completed), total: Double(backup.total))
                    } else {
                        ProgressView()
                    }
                    Text(backup.phase)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !backup.status.isEmpty {
                    Text(backup.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("备份")
            } footer: {
                Text("导出会下载各期文字和全部图片，打成一个 zip，保存到文件或 iCloud 云盘。没下到的图片会单独计数。导入把备份并进这台手机，已有的期数不会重复。图片存在本机，之后断网也能看。")
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
        .fileExporter(
            isPresented: $backup.showExporter,
            document: backup.exportFile,
            contentType: .zip,
            defaultFilename: "猫头鹰备份"
        ) { result in
            backup.noteExport(result)
        }
        .fileImporter(isPresented: $backup.showImporter, allowedContentTypes: [.zip]) { result in
            Task { await backup.importFile(result, model: model) }
        }
        .task { await reminders.sync() }
    }
}
