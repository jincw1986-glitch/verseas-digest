import SwiftUI
import UserNotifications

@main
struct OverseasDigestApp: App {
    @StateObject private var model = DigestModel()
    @StateObject private var reminders = ReminderSettings()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(reminders)
                .tint(.accentColor)
        }
    }
}
