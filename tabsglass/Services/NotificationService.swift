//
//  NotificationService.swift
//  tabsglass
//

import Foundation
import UserNotifications
import os.log

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "tabsglass", category: "Notifications")

    private init() {}

    // MARK: - Authorization

    /// Request notification authorization
    /// Returns true if authorized, false otherwise
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification authorization: \(granted ? "granted" : "denied")")
            return granted
        } catch {
            logger.error("Failed to request notification authorization: \(error.localizedDescription)")
            return false
        }
    }

    /// Check current authorization status
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Schedule Reminder

    /// Schedule a reminder notification for a message
    /// - Parameters:
    ///   - message: The message to remind about
    ///   - date: When to send the notification
    ///   - repeatInterval: How often to repeat (nil or .never for one-time)
    /// - Returns: The notification ID if successful
    func scheduleReminder(
        for message: Message,
        date: Date,
        repeatInterval: ReminderRepeatInterval?
    ) async -> String? {
        // Check authorization first
        let status = await checkAuthorizationStatus()

        if status == .notDetermined {
            let granted = await requestAuthorization()
            if !granted { return nil }
        } else if status == .denied {
            logger.warning("Notifications denied by user")
            return nil
        }

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = L10n.Reminder.notificationTitle

        let messageText = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if messageText.isEmpty {
            if message.isTodoList {
                content.body = message.todoTitle ?? L10n.Reminder.notificationBodyEmpty
            } else {
                content.body = L10n.Reminder.notificationBodyEmpty
            }
        } else {
            // Truncate long messages
            let maxLength = 100
            if messageText.count > maxLength {
                content.body = String(messageText.prefix(maxLength)) + "..."
            } else {
                content.body = messageText
            }
        }

        content.sound = .default
        content.userInfo = ["messageId": message.id.uuidString]

        // Create trigger based on repeat interval
        let trigger = createTrigger(for: date, repeatInterval: repeatInterval)

        // Generate unique notification ID
        let notificationId = UUID().uuidString

        let request = UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            logger.info("Scheduled reminder \(notificationId) for \(date)")
            return notificationId
        } catch {
            logger.error("Failed to schedule reminder: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Cancel Reminder

    /// Cancel a scheduled reminder
    func cancelReminder(notificationId: String) {
        center.removePendingNotificationRequests(withIdentifiers: [notificationId])
        logger.info("Cancelled reminder \(notificationId)")
    }

    /// Cancel multiple reminders
    func cancelReminders(notificationIds: [String]) {
        guard !notificationIds.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: notificationIds)
        logger.info("Cancelled \(notificationIds.count) reminders")
    }

    // MARK: - Private Helpers

    private func createTrigger(
        for date: Date,
        repeatInterval: ReminderRepeatInterval?
    ) -> UNNotificationTrigger {
        let calendar = Calendar.current
        let interval = repeatInterval ?? .never

        switch interval {
        case .never:
            // One-time notification: year, month, day, hour, minute
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            )
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        case .daily:
            // Daily: hour, minute
            let components = calendar.dateComponents([.hour, .minute], from: date)
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        case .weekly:
            // Weekly: weekday, hour, minute
            let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        case .biweekly:
            // Biweekly: use time interval (14 days)
            let seconds: TimeInterval = 14 * 24 * 60 * 60
            return UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: true)

        case .monthly:
            // Monthly: day, hour, minute
            let components = calendar.dateComponents([.day, .hour, .minute], from: date)
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        case .quarterly:
            // Quarterly: use time interval (~91 days)
            let seconds: TimeInterval = 91 * 24 * 60 * 60
            return UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: true)

        case .semiannually:
            // Semiannually: use time interval (~182 days)
            let seconds: TimeInterval = 182 * 24 * 60 * 60
            return UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: true)

        case .yearly:
            // Yearly: month, day, hour, minute
            let components = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        }
    }
}
