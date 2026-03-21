import Foundation
import EventKit

/// Provides calendar access: view today's events, upcoming meetings, and create new events.
final class CalendarTool: NativeTool, @unchecked Sendable {
    let name = "calendar"
    let description = "View today's calendar events, check upcoming meetings, or create new events. Can answer 'what's my next meeting?', 'what's on my schedule today?', or 'add a meeting at 3pm tomorrow'."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "action": [
                "type": "string",
                "description": "Action: 'today' for today's events, 'next' for next upcoming event, 'upcoming' for next 7 days, 'create' to add a new event."
            ],
            "title": [
                "type": "string",
                "description": "Event title (required for 'create')"
            ],
            "date": [
                "type": "string",
                "description": "Date string for create, e.g. '2025-03-18' or 'tomorrow'. Defaults to today."
            ],
            "start_time": [
                "type": "string",
                "description": "Start time for create, e.g. '15:00' or '3pm'"
            ],
            "duration_minutes": [
                "type": "integer",
                "description": "Duration in minutes for create. Defaults to 60."
            ],
            "location": [
                "type": "string",
                "description": "Location for the event (optional, for create)"
            ]
        ],
        "required": ["action"]
    ]

    private let eventStore = EKEventStore()

    func execute(args: [String: Any]) async throws -> String {
        // Request calendar access
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = try await eventStore.requestFullAccessToEvents()
        } else {
            granted = try await eventStore.requestAccess(to: .event)
        }

        guard granted else {
            return "Calendar access denied. Please enable calendar access in Settings > Privacy > Calendars."
        }

        let action = (args["action"] as? String ?? "today").lowercased()

        switch action {
        case "today", "schedule":
            return getTodayEvents()
        case "next":
            return getNextEvent()
        case "upcoming", "week", "this_week":
            return getUpcomingEvents(days: 7)
        case "tomorrow":
            return getTomorrowEvents()
        case "create", "add":
            return createEvent(args: args)
        default:
            return "Unknown action '\(action)'. Use: today, next, upcoming, tomorrow, or create."
        }
    }

    private func getTodayEvents() -> String {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        guard !events.isEmpty else {
            return "Your calendar is clear today. No events scheduled."
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        let descriptions = events.map { event -> String in
            var desc = "\(formatter.string(from: event.startDate)): \(event.title ?? "Untitled")"
            if event.isAllDay {
                desc = "All day: \(event.title ?? "Untitled")"
            }
            if let location = event.location, !location.isEmpty {
                desc += " at \(location)"
            }
            return desc
        }

        return "Today's schedule (\(events.count) event\(events.count == 1 ? "" : "s")): \(descriptions.joined(separator: ". "))."
    }

    private func getTomorrowEvents() -> String {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        let endOfTomorrow = calendar.date(byAdding: .day, value: 1, to: tomorrow)!

        let predicate = eventStore.predicateForEvents(withStart: tomorrow, end: endOfTomorrow, calendars: nil)
        let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        guard !events.isEmpty else {
            return "No events scheduled for tomorrow."
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        let descriptions = events.map { event -> String in
            var desc = "\(formatter.string(from: event.startDate)): \(event.title ?? "Untitled")"
            if event.isAllDay {
                desc = "All day: \(event.title ?? "Untitled")"
            }
            if let location = event.location, !location.isEmpty {
                desc += " at \(location)"
            }
            return desc
        }

        return "Tomorrow's schedule (\(events.count) event\(events.count == 1 ? "" : "s")): \(descriptions.joined(separator: ". "))."
    }

    private func getNextEvent() -> String {
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: now)!

        let predicate = eventStore.predicateForEvents(withStart: now, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        guard let next = events.first else {
            return "No upcoming events in the next 7 days."
        }

        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(next.startDate) {
            formatter.dateFormat = "h:mm a"
            let timeStr = formatter.string(from: next.startDate)
            let minsUntil = Int(next.startDate.timeIntervalSince(now) / 60)

            var desc = "Next up: \(next.title ?? "Untitled") at \(timeStr)"
            if minsUntil > 0 {
                if minsUntil < 60 {
                    desc += " (in \(minsUntil) minute\(minsUntil == 1 ? "" : "s"))"
                } else {
                    let hours = minsUntil / 60
                    let mins = minsUntil % 60
                    desc += " (in \(hours)h\(mins > 0 ? " \(mins)m" : ""))"
                }
            }
            if let location = next.location, !location.isEmpty {
                desc += " at \(location)"
            }
            return desc + "."
        } else {
            formatter.dateFormat = "EEEE 'at' h:mm a"
            var desc = "Next up: \(next.title ?? "Untitled") on \(formatter.string(from: next.startDate))"
            if let location = next.location, !location.isEmpty {
                desc += " at \(location)"
            }
            return desc + "."
        }
    }

    private func getUpcomingEvents(days: Int) -> String {
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: start)!

        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        guard !events.isEmpty else {
            return "No events in the next \(days) days."
        }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        let descriptions = events.prefix(10).map { event -> String in
            let day = Calendar.current.isDateInToday(event.startDate) ? "Today" :
                      Calendar.current.isDateInTomorrow(event.startDate) ? "Tomorrow" :
                      dayFormatter.string(from: event.startDate)
            if event.isAllDay {
                return "\(day): \(event.title ?? "Untitled") (all day)"
            }
            return "\(day) \(timeFormatter.string(from: event.startDate)): \(event.title ?? "Untitled")"
        }

        var result = "Upcoming (\(events.count) event\(events.count == 1 ? "" : "s")): \(descriptions.joined(separator: ". "))."
        if events.count > 10 {
            result += " Plus \(events.count - 10) more."
        }
        return result
    }

    private func createEvent(args: [String: Any]) -> String {
        guard let title = args["title"] as? String, !title.isEmpty else {
            return "No event title provided."
        }

        let calendar = Calendar.current
        var startDate: Date

        // Parse date
        let dateStr = (args["date"] as? String ?? "").lowercased()
        if dateStr == "tomorrow" {
            startDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        } else if let parsed = parseDate(dateStr) {
            startDate = parsed
        } else {
            startDate = calendar.startOfDay(for: Date())
        }

        // Parse time
        if let timeStr = args["start_time"] as? String, let time = parseTime(timeStr) {
            startDate = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: startDate)!
        } else {
            // Default to next hour
            let hour = calendar.component(.hour, from: Date()) + 1
            startDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: startDate)!
        }

        let durationMinutes = (args["duration_minutes"] as? Int) ?? 60
        let endDate = calendar.date(byAdding: .minute, value: durationMinutes, to: startDate)!

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = eventStore.defaultCalendarForNewEvents
        if let location = args["location"] as? String {
            event.location = location
        }

        // Add a default alert 15 minutes before
        event.addAlarm(EKAlarm(relativeOffset: -900))

        do {
            try eventStore.save(event, span: .thisEvent)
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d 'at' h:mm a"
            var result = "Created: '\(title)' on \(formatter.string(from: startDate)) (\(durationMinutes) min)"
            if let location = args["location"] as? String {
                result += " at \(location)"
            }
            result += ". You'll get a reminder 15 minutes before."
            return result
        } catch {
            return "Couldn't create event: \(error.localizedDescription)"
        }
    }

    private func parseDate(_ str: String) -> Date? {
        let formatter = DateFormatter()
        for format in ["yyyy-MM-dd", "MM/dd/yyyy", "MM-dd-yyyy", "MMM d", "MMMM d"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: str) {
                // Set year to current if not specified
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

        // Try "3pm", "3:30pm", "15:00"
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
