import Combine
import Foundation
import UserNotifications

@MainActor
final class ReminderSettings: ObservableObject {
    static let requestID = "daily-digest-0800"
    private let defaultsKey = "dailyReminderEnabled"
    private let center = UNUserNotificationCenter.current()

    @Published var isOn: Bool
    @Published var statusMessage = "关闭时不会发出提醒。"
    @Published var nextFire: Date?
    @Published var needsSystemSettings = false

    init() {
        isOn = UserDefaults.standard.bool(forKey: defaultsKey)
    }

    func sync() async {
        let settings = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests()
        nextFire = nextDate(in: pending)
        let allowed = Self.isAllowed(settings.authorizationStatus)
        needsSystemSettings = isOn && settings.authorizationStatus == .denied
        if isOn && allowed && nextFire == nil {
            await schedule()
            let refreshed = await center.pendingNotificationRequests()
            nextFire = nextDate(in: refreshed)
        }
        if !isOn {
            statusMessage = "关闭时不会发出提醒。"
        } else if allowed {
            statusMessage = "已设好。每天当地时间 8:00 会提示：今天的海外资讯简报已更新。"
        } else if settings.authorizationStatus == .denied {
            statusMessage = "通知权限已关闭。请到系统设置里允许“海外简报”发送通知。"
        } else {
            statusMessage = "还没有通知权限。打开开关后，系统会询问一次。"
        }
    }

    func setOn(_ on: Bool) async {
        if !on {
            center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
            isOn = false
            UserDefaults.standard.set(false, forKey: defaultsKey)
            nextFire = nil
            needsSystemSettings = false
            statusMessage = "每日提醒已关闭。"
            return
        }

        isOn = true
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        guard Self.isAllowed(settings.authorizationStatus) else {
            isOn = false
            UserDefaults.standard.set(false, forKey: defaultsKey)
            needsSystemSettings = settings.authorizationStatus == .denied
            statusMessage = settings.authorizationStatus == .denied
                ? "通知权限已关闭。请到系统设置里允许“海外简报”发送通知。"
                : "没有获得通知权限，无法在早上 8:00 提醒。"
            return
        }

        await schedule()
        UserDefaults.standard.set(true, forKey: defaultsKey)
        needsSystemSettings = false
        let pending = await center.pendingNotificationRequests()
        nextFire = nextDate(in: pending)
        statusMessage = "已设好。每天当地时间 8:00 会提示：今天的海外资讯简报已更新。"
    }

    private func schedule() async {
        var components = DateComponents()
        components.hour = 8
        components.minute = 0
        let content = UNMutableNotificationContent()
        content.title = "海外简报"
        content.body = "今天的海外资讯简报已更新"
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: Self.requestID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func nextDate(in requests: [UNNotificationRequest]) -> Date? {
        let match = requests.first { $0.identifier == Self.requestID }
        return (match?.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
    }

    private static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }
}

final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
