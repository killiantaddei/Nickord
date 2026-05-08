import Foundation
import UserNotifications
import UIKit

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized = false
    @Published var pendingNotificationCount = 0

    private init() {
        Task { await checkAuthorization() }
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            Task { @MainActor in
                self.isAuthorized = granted
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func checkAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Friend Request Notifications

    func sendFriendRequestNotification(fromUsername: String) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Nuova richiesta di amicizia"
        content.body = "\(fromUsername) vuole aggiungerti come amico"
        content.sound = .default
        content.categoryIdentifier = "FRIEND_REQUEST"

        let request = UNNotificationRequest(
            identifier: "friend_request_\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
        pendingNotificationCount += 1
    }

    func sendFriendAcceptedNotification(username: String) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Richiesta accettata"
        content.body = "\(username) ha accettato la tua richiesta di amicizia"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "friend_accepted_\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Message Notifications

    func sendMessageNotification(fromUsername: String, message: String, roomName: String? = nil) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        if let room = roomName {
            content.title = "\(room)"
            content.body = "\(fromUsername): \(message)"
        } else {
            content.title = fromUsername
            content.body = message
        }
        content.sound = .default
        content.categoryIdentifier = "MESSAGE"

        let request = UNNotificationRequest(
            identifier: "message_\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Call Notifications

    func sendCallNotification(fromUsername: String, isVideo: Bool) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = isVideo ? "Videochiamata in arrivo" : "Chiamata in arrivo"
        content.body = "\(fromUsername) ti sta chiamando"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("ringtone.caf"))
        content.categoryIdentifier = "INCOMING_CALL"
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "call_\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Badge Management

    func clearBadge() {
        pendingNotificationCount = 0
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    func updateBadge(count: Int) {
        pendingNotificationCount = count
        UNUserNotificationCenter.current().setBadgeCount(count)
    }

    // MARK: - Remove Notifications

    func removeAllDelivered() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    func setupCategories() {
        let acceptAction = UNNotificationAction(
            identifier: "ACCEPT_FRIEND",
            title: "Accetta",
            options: [.foreground]
        )
        let declineAction = UNNotificationAction(
            identifier: "DECLINE_FRIEND",
            title: "Rifiuta",
            options: [.destructive]
        )
        let friendRequestCategory = UNNotificationCategory(
            identifier: "FRIEND_REQUEST",
            actions: [acceptAction, declineAction],
            intentIdentifiers: []
        )

        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY_MESSAGE",
            title: "Rispondi",
            options: [.foreground],
            textInputButtonTitle: "Invia",
            textInputPlaceholder: "Scrivi un messaggio..."
        )
        let messageCategory = UNNotificationCategory(
            identifier: "MESSAGE",
            actions: [replyAction],
            intentIdentifiers: []
        )

        let answerAction = UNNotificationAction(
            identifier: "ANSWER_CALL",
            title: "Rispondi",
            options: [.foreground]
        )
        let declineCallAction = UNNotificationAction(
            identifier: "DECLINE_CALL",
            title: "Rifiuta",
            options: [.destructive]
        )
        let callCategory = UNNotificationCategory(
            identifier: "INCOMING_CALL",
            actions: [answerAction, declineCallAction],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            friendRequestCategory,
            messageCategory,
            callCategory
        ])
    }
}
