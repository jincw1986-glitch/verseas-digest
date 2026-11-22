import SwiftUI
import UserNotifications

enum DigestAppearance: String {
    static let storageKey = "digestAppearance"

    case system, day, night

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .day: .light
        case .night: .dark
        }
    }
}

@main
struct OverseasDigestApp: App {
    @StateObject private var model = DigestModel()
    @StateObject private var reminders = ReminderSettings()
    @AppStorage(DigestAppearance.storageKey) private var appearance: DigestAppearance = .system

    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(reminders)
                .tint(.accentColor)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
