import Foundation
import UserNotifications

/// Sets alarms using high-priority local notifications with a repeating sound.
/// Unlike timers (relative delay), alarms fire at a specific clock time.
struct AlarmTool: NativeTool {
    let name = "set_alarm"
    let description = "Set an alarm for a specific time. Unlike a timer, an alarm fires at a clock time (e.g. '7:00 AM'). Supports 'tomorrow', specific dates, or today by default."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "time": [
                "type": "string",
                "description": "The time for the alarm, e.g. '7:00 AM', '6:30', '22:00'"
            ],
            "date": [
                "type": "string",
                "description": "Date for the alarm: 'tomorrow', 'today', or 'YYYY-MM-DD'. Defaults to next occurrence of the time."
            ],
            "label": [
                "type": "string",
                "description": "Label for the alarm, e.g. 'Wake up', 'Take medicine'"
            ],
            "action": [
                "type": "string",
                "description": "Action: 'set' to create alarm, 'list' to show pending alarms, 'cancel_all' to remove all alarms. Defaults to 'set'."
            ]
        ],
        "required": [] as [String]
    ]

    private static let alarmPrefix = "alarm-"

    func execute(args: [String: Any]) async throws -> String {
        let action = (args["action"] as? String ?? "set").lowercased()

        switch action {
        case "list", "show":
            return await listAlarms()
        case "cancel_all", "cancel", "clear":
            return await cancelAllAlarms()
        default:
            return await setAlarm(args: args)
        }
    }

    private func setAlarm(args: [String: Any]) async -> String {
        guard let timeStr = args["time"] as? String, !timeStr.isEmpty else {
            return "No time provided. Say something like 'set an alarm for 7 AM'."
        }

        guard let time = parseTime(timeStr) else {
            return "Couldn't parse time '\(timeStr)'. Try formats like '7:00 AM', '6:30', or '22:00'."
        }

        let label = args["label"] as? String ?? "Alarm"
        let dateStr = (args["date"] as? String ?? "").lowercased()

        let calendar = Calendar.current
        var alarmDate: Date

        if dateStr == "tomorrow" {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
            alarmDate = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: tomorrow)!
        } else if let parsed = parseDate(dateStr) {
            alarmDate = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: parsed)!
        } else {
            // Default: next occurrence (today if in the future, tomorrow if already passed)
            var target = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date())!
            if target <= Date() {
                target = calendar.date(byAdding: .day, value: 1, to: target)!
            }
            alarmDate = target
        }

        // Request notification permission
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let granted = try? await center.requestAuthorization(options: [.alert, .sound, .criticalAlert])
            if granted != true {
                return "Alarm set for \(formatAlarmTime(alarmDate)), but notifications are disabled. You won't hear it."
            }
        }

        // Create notification with calendar trigger (specific date/time)
        let content = UNMutableNotificationContent()
        content.title = label
        content.body = "Alarm: \(label) — \(formatAlarmTime(alarmDate))"
        content.sound = UNNotificationSound.defaultCritical // Louder than default
        content.interruptionLevel = .timeSensitive

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: alarmDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let requestId = "\(Self.alarmPrefix)\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            return "Couldn't set alarm: \(error.localizedDescription)"
        }

        let timeUntil = alarmDate.timeIntervalSince(Date())
        let hoursUntil = Int(timeUntil) / 3600
        let minsUntil = (Int(timeUntil) % 3600) / 60

        var response = "Alarm set: \(label) at \(formatAlarmTime(alarmDate))"
        if hoursUntil > 0 {
            response += " (\(hoursUntil)h \(minsUntil)m from now)"
        } else if minsUntil > 0 {
            response += " (\(minsUntil) minutes from now)"
        }
        response += "."
        return response
    }

    private func listAlarms() async -> String {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let alarms = pending.filter { $0.identifier.hasPrefix(Self.alarmPrefix) }

        guard !alarms.isEmpty else {
            return "No alarms set."
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE h:mm a"

        let descriptions = alarms.compactMap { req -> String? in
            guard let trigger = req.trigger as? UNCalendarNotificationTrigger,
                  let date = trigger.nextTriggerDate() else { return nil }
            return "\(req.content.title): \(formatter.string(from: date))"
        }

        return "\(alarms.count) alarm\(alarms.count == 1 ? "" : "s"): \(descriptions.joined(separator: ". "))."
    }

    private func cancelAllAlarms() async -> String {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let alarmIds = pending.filter { $0.identifier.hasPrefix(Self.alarmPrefix) }.map { $0.identifier }

        guard !alarmIds.isEmpty else {
            return "No alarms to cancel."
        }

        center.removePendingNotificationRequests(withIdentifiers: alarmIds)
        return "Cancelled \(alarmIds.count) alarm\(alarmIds.count == 1 ? "" : "s")."
    }

    private func formatAlarmTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
            return "today at \(formatter.string(from: date))"
        } else if calendar.isDateInTomorrow(date) {
            formatter.dateFormat = "h:mm a"
            return "tomorrow at \(formatter.string(from: date))"
        } else {
            formatter.dateFormat = "EEEE, MMM d 'at' h:mm a"
            return formatter.string(from: date)
        }
    }

    private func parseTime(_ str: String) -> (hour: Int, minute: Int)? {
        let cleaned = str.lowercased().trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        for format in ["h:mm a", "h:mma", "ha", "h a", "HH:mm", "H:mm", "HHmm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) {
                let cal = Calendar.current
                return (cal.component(.hour, from: date), cal.component(.minute, from: date))
            }
        }
        return nil
    }

    private func parseDate(_ str: String) -> Date? {
        guard !str.isEmpty else { return nil }
        let formatter = DateFormatter()
        for format in ["yyyy-MM-dd", "MM/dd/yyyy", "MMM d"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: str) {
                let cal = Calendar.current
                var components = cal.dateComponents([.month, .day], from: date)
                components.year = cal.component(.year, from: Date())
                return cal.date(from: components)
            }
        }
        return nil
    }
}
