import Foundation

/// Provides a daily briefing combining weather, date/time, and news headlines.
struct DailyBriefingTool: NativeTool {
    let name = "daily_briefing"
    let description = "Get a daily briefing with current date/time, weather forecast, and top news headlines. Perfect for 'good morning' or 'what's happening today' requests."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "news_topic": [
                "type": "string",
                "description": "Optional news topic to focus on, e.g. 'technology', 'sports'. Defaults to general top headlines."
            ]
        ],
        "required": [] as [String]
    ]

    private let weatherTool: WeatherTool
    private let newsTool: NewsTool
    private let dateTimeTool: DateTimeTool

    init(weatherTool: WeatherTool, newsTool: NewsTool, dateTimeTool: DateTimeTool) {
        self.weatherTool = weatherTool
        self.newsTool = newsTool
        self.dateTimeTool = dateTimeTool
    }

    func execute(args: [String: Any]) async throws -> String {
        // Run all three in parallel
        async let dateResult = dateTimeTool.execute(args: [:])
        async let weatherResult = weatherTool.execute(args: [:])

        let newsTopic = args["news_topic"] as? String
        let newsArgs: [String: Any] = newsTopic != nil ? ["topic": newsTopic!, "count": 5] : ["count": 5]
        async let newsResult = newsTool.execute(args: newsArgs)

        let date = try await dateResult
        let weather = try await weatherResult
        let news = try await newsResult

        var briefing = "📅 DATE & TIME:\n\(date)\n\n"
        briefing += "🌤 WEATHER:\n\(weather)\n\n"
        briefing += "📰 NEWS:\n\(news)"

        return briefing
    }
}
