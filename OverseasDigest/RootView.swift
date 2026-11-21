import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: DigestModel
    @EnvironmentObject private var reminders: ReminderSettings

    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("今日", systemImage: "newspaper")
            }

            NavigationStack {
                ArchiveView()
            }
            .tabItem {
                Label("往期", systemImage: "books.vertical")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
        .task {
            await reminders.sync()
            await model.refresh()
        }
    }
}
