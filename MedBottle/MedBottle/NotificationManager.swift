import Foundation
@preconcurrency import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationManager()

    private enum Identifier {
        static let category = "MEDICATION_REMINDER"
        static let logAsTakenAction = "LOG_AS_TAKEN"
        static let snoozeAction = "SNOOZE_15_MIN"
        static let medicationID = "medicationID"
        static let reminderID = "reminderID"
        static let medicationName = "medicationName"
        static let dosageAmount = "dosageAmount"
    }

    private let center = UNUserNotificationCenter.current()
    private weak var store: MedicationStore?

    private override init() {
        super.init()
        registerCategories()
    }

    func configure(store: MedicationStore? = nil) {
        if let store {
            self.store = store
        }
        center.delegate = self
        registerCategories()
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                print("[NotificationManager] Authorization request failed: \(error)")
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func scheduleAllReminders(for medications: [Medication]) {
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else {
                return
            }

            for medication in medications {
                await scheduleRemindersAsync(for: medication)
            }
        }
    }

    func scheduleReminders(for medication: Medication) {
        Task { await scheduleRemindersAsync(for: medication) }
    }

    func removeReminders(for medicationID: Medication.ID) {
        center.getPendingNotificationRequests { [center] requests in
            let medicationIDString = medicationID.uuidString
            let identifiers = requests.compactMap { request -> String? in
                guard request.content.userInfo[Identifier.medicationID] as? String == medicationIDString else {
                    return nil
                }
                return request.identifier
            }

            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    private func scheduleRemindersAsync(for medication: Medication) async {
        await removePendingReminders(for: medication.id)

        for reminder in medication.reminders where reminder.isActive && reminder.frequency != .asNeeded {
            let triggers = triggers(for: reminder)

            for (index, trigger) in triggers.enumerated() {
                let content = notificationContent(for: medication, reminder: reminder)
                let request = UNNotificationRequest(
                    identifier: requestIdentifier(for: medication.id, reminderID: reminder.id, index: index),
                    content: content,
                    trigger: trigger
                )

                do {
                    try await center.add(request)
                } catch {
                    print("[NotificationManager] Failed to schedule reminder \(reminder.id) for \(medication.name): \(error)")
                }
            }
        }
    }

    private func removePendingReminders(for medicationID: Medication.ID) async {
        let requests = await center.pendingNotificationRequests()
        let medicationIDString = medicationID.uuidString
        let identifiers = requests.compactMap { request -> String? in
            guard request.content.userInfo[Identifier.medicationID] as? String == medicationIDString,
                  !request.identifier.contains("snooze") else {
                return nil
            }
            return request.identifier
        }

        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func triggers(for reminder: Medication.Reminder) -> [UNCalendarNotificationTrigger] {
        var timeComponents = Calendar.current.dateComponents([.hour, .minute], from: reminder.time)

        switch reminder.frequency {
        case .daily:
            return [UNCalendarNotificationTrigger(dateMatching: timeComponents, repeats: true)]
        case .specificDays:
            return reminder.weekdays.sorted { $0.rawValue < $1.rawValue }.map { weekday in
                timeComponents.weekday = weekday.rawValue
                return UNCalendarNotificationTrigger(dateMatching: timeComponents, repeats: true)
            }
        case .asNeeded:
            return []
        }
    }

    private func notificationContent(for medication: Medication, reminder: Medication.Reminder) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Time for \(medication.name)"
        content.body = "Take \(reminder.dosageAmount) tablet\(reminder.dosageAmount == 1 ? "" : "s")."
        content.sound = .default
        content.categoryIdentifier = Identifier.category
        content.threadIdentifier = medication.id.uuidString
        content.userInfo = [
            Identifier.medicationID: medication.id.uuidString,
            Identifier.reminderID: reminder.id.uuidString,
            Identifier.medicationName: medication.name,
            Identifier.dosageAmount: reminder.dosageAmount
        ]
        return content
    }

    private func requestIdentifier(for medicationID: Medication.ID, reminderID: Medication.Reminder.ID, index: Int) -> String {
        "medication-reminder-\(medicationID.uuidString)-\(reminderID.uuidString)-\(index)"
    }

    private func registerCategories() {
        let logAsTaken = UNNotificationAction(
            identifier: Identifier.logAsTakenAction,
            title: "Log as Taken",
            options: []
        )

        let snooze = UNNotificationAction(
            identifier: Identifier.snoozeAction,
            title: "Snooze (15 Min)",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: Identifier.category,
            actions: [logAsTaken, snooze],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([category])
    }

    private func handleLogAsTaken(userInfo: [AnyHashable: Any], completionHandler: @escaping @Sendable () -> Void) {
        guard let medicationID = medicationID(from: userInfo) else {
            completionHandler()
            return
        }

        let dosageAmount = userInfo[Identifier.dosageAmount] as? Int ?? 1
        let takenAt = Date()

        Task { @MainActor [weak self] in
            if let store = self?.store {
                store.logDose(forMedicationID: medicationID, dosageAmount: dosageAmount, takenAt: takenAt)
            } else {
                MedicationStore.persistNotificationDose(
                    medicationID: medicationID,
                    dosageAmount: dosageAmount,
                    takenAt: takenAt
                )
            }
            completionHandler()
        }
    }

    private func handleSnooze(userInfo: [AnyHashable: Any], completionHandler: @escaping @Sendable () -> Void) {
        guard let medicationID = medicationID(from: userInfo) else {
            completionHandler()
            return
        }

        let reminderID = reminderID(from: userInfo) ?? UUID()
        let medicationName = userInfo[Identifier.medicationName] as? String ?? "your medication"
        let dosageAmount = userInfo[Identifier.dosageAmount] as? Int ?? 1

        let content = UNMutableNotificationContent()
        content.title = "Reminder: \(medicationName)"
        content.body = "Take \(dosageAmount) tablet\(dosageAmount == 1 ? "" : "s")."
        content.sound = .default
        content.categoryIdentifier = Identifier.category
        content.threadIdentifier = medicationID.uuidString
        content.userInfo = [
            Identifier.medicationID: medicationID.uuidString,
            Identifier.reminderID: reminderID.uuidString,
            Identifier.medicationName: medicationName,
            Identifier.dosageAmount: dosageAmount
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
        let request = UNNotificationRequest(
            identifier: "medication-snooze-\(medicationID.uuidString)-\(reminderID.uuidString)-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("[NotificationManager] Failed to schedule snooze: \(error)")
            }
            completionHandler()
        }
    }

    private func medicationID(from userInfo: [AnyHashable: Any]) -> Medication.ID? {
        guard let idString = userInfo[Identifier.medicationID] as? String else { return nil }
        return UUID(uuidString: idString)
    }

    private func reminderID(from userInfo: [AnyHashable: Any]) -> Medication.Reminder.ID? {
        guard let idString = userInfo[Identifier.reminderID] as? String else { return nil }
        return UUID(uuidString: idString)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        switch response.actionIdentifier {
        case Identifier.logAsTakenAction:
            handleLogAsTaken(userInfo: response.notification.request.content.userInfo, completionHandler: completionHandler)
        case Identifier.snoozeAction:
            handleSnooze(userInfo: response.notification.request.content.userInfo, completionHandler: completionHandler)
        default:
            completionHandler()
        }
    }
}
