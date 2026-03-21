import Foundation
import EventKit

/// Creates and lists Apple Reminders, with optional due dates and location triggers.
/// These are real iOS reminders that sync with iCloud and trigger notifications.
final class AppleRemindersTool: NativeTool, @unchecked Sendable {
    let name = "reminder"
    let description = "Create or list Apple Reminders. Supports due dates and notifications. These sync with iCloud and appear in the Reminders app. Great for 'remind me to buy milk', 'remind me at 5pm to call John'."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "action": [
                "type": "string",
                "description": "Action: 'create' to add a reminder, 'list' to show incomplete reminders, 'complete' to mark one done."
            ],
            "title": [
                "type": "string",
                "description": "Reminder text (required for 'create')"
            ],
            "due_date": [
                "type": "string",
                "description": "Due date, e.g. '2025-03-18', 'tomorrow', 'tonight'. Optional."
            ],
            "due_time": [
                "type": "string",
                "description": "Due time, e.g. '17:00' or '5pm'. If set, triggers a notification at this time."
            ],
            "search": [
                "type": "string",
                "description": "Search term for 'complete' action to find the reminder to complete."
            ]
        ],
        "required": ["action"]
    ]

    private let eventStore = EKEventStore()

    func execute(args: [String: Any]) async throws -> String {
        // Request reminders access
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = try await eventStore.requestFullAccessToReminders()
        } else {
            granted = try await eventStore.requestAccess(to: .reminder)
        }

        guard granted else {
            return "Reminders access denied. Please enable it in Settings > Privacy > Reminders."
        }

        let action = (args["action"] as? String ?? "create").lowercased()

        switch action {
        case "create", "add", "set":
            return try createReminder(args: args)
        case "list", "show":
            return await listReminders()
        case "complete", "done", "finish":
            return await completeReminder(args: args)
        default:
            return "Unknown action '\(action)'. Use: create, list, or complete."
        }
    }

    private func createReminder(args: [String: Any]) throws -> String {
        guard let title = args["title"] as? String, !title.isEmpty else {
            return "No reminder text provided."
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        // Parse due date
        var hasDueDate = false
        let dateStr = (args["due_date"] as? String ?? "").lowercased()
        let timeStr = args["due_time"] as? String

        let calendar = Calendar.current
        var dueDate: Date?

        if dateStr == "tomorrow" {
            dueDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
        } else if dateStr == "tonight" || dateStr == "today" {
            dueDate = calendar.startOfDay(for: Date())
            if timeStr == nil && dateStr == "tonight" {
                dueDate = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: Date())
            }
        } else if !dateStr.isEmpty {
            dueDate = parseDate(dateStr)
        }

        // Apply time
        if let timeStr, let time = parseTime(timeStr) {
            let base = dueDate ?? calendar.startOfDay(for: Date())
            dueDate = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: base)
            hasDueDate = true
        } else if dueDate != nil {
            hasDueDate = true
        }

        if let dueDate, hasDueDate {
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.dueDateComponents = components

            // Add alarm if we have a specific time
            if timeStr != nil {
                reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
            }
        }

        try eventStore.save(reminder, commit: true)

        var response = "Reminder set: '\(title)'"
        if let dueDate, hasDueDate {
            let formatter = DateFormatter()
            if timeStr != nil {
                formatter.dateFormat = "EEEE, MMM d 'at' h:mm a"
            } else {
                formatter.dateFormat = "EEEE, MMM d"
            }
            response += " due \(formatter.string(from: dueDate))"
            if timeStr != nil {
                response += ". You'll get a notification at that time"
            }
        }
        response += "."
        return response
    }

    private func listReminders() async -> String {
        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: calendars
        )

        let reminders = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }

        guard !reminders.isEmpty else {
            return "No incomplete reminders."
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        let descriptions = reminders.prefix(10).map { rem -> String in
            var desc = rem.title ?? "Untitled"
            if let due = rem.dueDateComponents, let date = Calendar.current.date(from: due) {
                if due.hour != nil {
                    desc += " (due \(formatter.string(from: date)) at \(timeFormatter.string(from: date)))"
                } else {
                    desc += " (due \(formatter.string(from: date)))"
                }
            }
            return desc
        }

        var result = "\(reminders.count) reminder\(reminders.count == 1 ? "" : "s"): \(descriptions.joined(separator: ". "))."
        if reminders.count > 10 {
            result += " Plus \(reminders.count - 10) more."
        }
        return result
    }

    private func completeReminder(args: [String: Any]) async -> String {
        guard let search = args["search"] as? String ?? args["title"] as? String, !search.isEmpty else {
            return "Tell me which reminder to complete."
        }

        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: calendars
        )

        let reminders = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }

        let term = search.lowercased()
        guard let match = reminders.first(where: { ($0.title ?? "").lowercased().contains(term) }) else {
            return "No incomplete reminder matching '\(search)'."
        }

        match.isCompleted = true
        do {
            try eventStore.save(match, commit: true)
            return "Marked '\(match.title ?? search)' as complete."
        } catch {
            return "Couldn't complete reminder: \(error.localizedDescription)"
        }
    }

    private func parseDate(_ str: String) -> Date? {
        let formatter = DateFormatter()
        for format in ["yyyy-MM-dd", "MM/dd/yyyy", "MMM d", "MMMM d"] {
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

    private func parseTime(_ str: String) -> (hour: Int, minute: Int)? {
        let cleaned = str.lowercased().trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        for format in ["h:mm a", "ha", "h a", "HH:mm", "H:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) {
                let cal = Calendar.current
                return (cal.component(.hour, from: date), cal.component(.minute, from: date))
            }
        }
        return nil
    }
}
