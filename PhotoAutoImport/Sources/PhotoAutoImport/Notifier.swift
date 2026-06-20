import Foundation
import UserNotifications

/// 系統通知。需要 App 以 .app bundle 形式執行（見 scripts/build_app.sh），
/// 直接用 `swift run` 跑裸執行檔時通知中心會無法使用。
enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
