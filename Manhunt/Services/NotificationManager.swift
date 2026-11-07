import Foundation
import UIKit
import UserNotifications

/// Local notifications for hunter alerts. They fire from the realtime
/// subscription, which stays alive in the background because every player's
/// app is running continuous background location during a game.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var center: UNUserNotificationCenter { .current() }

    func requestAuthorization() async {
        center.delegate = self
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func notify(title: String, body: String, urgent: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = urgent ? .timeSensitive : .active
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))

        DispatchQueue.main.async {
            UINotificationFeedbackGenerator().notificationOccurred(urgent ? .warning : .success)
        }
    }

    // Show banners even while the app is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
