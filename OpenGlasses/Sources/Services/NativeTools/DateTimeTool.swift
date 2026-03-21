import Foundation

/// Returns the current date, time, and day of week. Pure local, no network needed.
struct DateTimeTool: NativeTool {
    let name = "get_datetime"
    let description = "Get the current date, time, and day of week. Optionally specify a timezone."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "timezone": [
                "type": "string",
                "description": "IANA timezone identifier, e.g. 'America/New_York', 'Europe/London'. Defaults to device timezone."
            ]
        ],
        "required": [] as [String]
    ]

    func execute(args: [String: Any]) async throws -> String {
        let timeZone: TimeZone
        if let tzString = args["timezone"] as? String, let tz = TimeZone(identifier: tzString) {
            timeZone = tz
        } else {
            timeZone = .current
        }

        let now = Date()
        let formatter = DateFormatter()
        formatter.timeZone = timeZone

        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        let dateStr = formatter.string(from: now)

        formatter.dateFormat = "h:mm a"
        let timeStr = formatter.string(from: now)

        let tzAbbrev = timeZone.abbreviation(for: now) ?? timeZone.identifier

        return "It's \(timeStr) on \(dateStr) (\(tzAbbrev))."
    }
}
