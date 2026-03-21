import Foundation
import UserNotifications

/// Sets a timer using local notifications. No external API needed.
struct TimerTool: NativeTool {
    let name = "set_timer"
    let description = "Set a timer that will notify the user after the specified duration."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "seconds": [
                "type": "integer",
                "description": "Timer duration in seconds"
            ],
            "label": [
                "type": "string",
                "description": "Optional label for the timer, e.g. 'pasta' or 'break time'"
            ]
        ],
        "required": ["seconds"]
    ]

    func execute(args: [String: Any]) async throws -> String {
        let seconds: Int
        if let s = args["seconds"] as? Int {
            seconds = s
        } else if let s = args["seconds"] as? Double {
            seconds = Int(s)
        } else {
            return "Missing timer duration."
        }

        guard seconds > 0 && seconds <= 86400 else {
            return "Timer must be between 1 second and 24 hours."
        }

        let label = args["label"] as? String

        // Request notification permission
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            if !granted {
                return "Timer set for \(formatDuration(seconds)), but notifications are disabled. You won't get an alert."
            }
        }

        // Create notification
        let content = UNMutableNotificationContent()
        content.title = label ?? "Timer"
        content.body = label != nil ? "Your \(label!) timer is done!" : "Timer complete!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let requestId = "timer-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)

        try await center.add(request)

        let durationStr = formatDuration(seconds)
        if let label {
            return "Timer set: \(label) for \(durationStr)."
        }
        return "Timer set for \(durationStr)."
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) second\(seconds == 1 ? "" : "s")"
        }
        let mins = seconds / 60
        let secs = seconds % 60
        if mins < 60 {
            if secs == 0 {
                return "\(mins) minute\(mins == 1 ? "" : "s")"
            }
            return "\(mins) minute\(mins == 1 ? "" : "s") and \(secs) second\(secs == 1 ? "" : "s")"
        }
        let hours = mins / 60
        let remainMins = mins % 60
        if remainMins == 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        return "\(hours) hour\(hours == 1 ? "" : "s") and \(remainMins) minute\(remainMins == 1 ? "" : "s")"
    }
}
