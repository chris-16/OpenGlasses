import Foundation

/// Tool for the memory rewind feature — "what did they just say?" or "what happened?"
/// Transcribes and summarizes recent ambient audio from the rolling buffer.
struct MemoryRewindTool: NativeTool {
    let name = "memory_rewind"
    let description = "Recall what was said recently. Transcribes the last few minutes of ambient audio and provides a summary. Use when the user asks 'what did they just say?', 'what happened?', 'recap the last few minutes', or similar."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "minutes": [
                "type": "number",
                "description": "How many minutes to rewind (default: 2, max: 10)"
            ],
            "action": [
                "type": "string",
                "description": "Action: 'rewind' (default), 'start' (enable buffering), 'stop' (disable), 'status'"
            ]
        ],
        "required": []
    ]

    weak var rewindService: MemoryRewindService?

    init(rewindService: MemoryRewindService) {
        self.rewindService = rewindService
    }

    func execute(args: [String: Any]) async throws -> String {
        guard let service = rewindService else {
            return "Memory rewind service not available."
        }

        let action = (args["action"] as? String)?.lowercased() ?? "rewind"

        switch action {
        case "start":
            await MainActor.run { service.start() }
            return "Memory rewind enabled. I'm now buffering ambient audio. Ask me 'what did they just say?' anytime to rewind."

        case "stop":
            await MainActor.run { service.stop() }
            return "Memory rewind disabled. Audio buffer cleared."

        case "status":
            let active = await MainActor.run { service.isActive }
            let duration = await MainActor.run { service.bufferDurationMinutes }
            if active {
                return "Memory rewind is active with \(String(format: "%.1f", duration)) minutes of audio buffered."
            } else {
                return "Memory rewind is not active. Say 'start memory rewind' to enable it."
            }

        case "rewind":
            let active = await MainActor.run { service.isActive }
            guard active else {
                return "Memory rewind is not active. Say 'start memory rewind' to enable it first."
            }
            let minutes = (args["minutes"] as? Double) ?? (args["minutes"] as? Int).map { Double($0) } ?? 2.0
            let clampedMinutes = max(0.5, min(10.0, minutes))
            return await service.rewind(lastMinutes: clampedMinutes)

        default:
            return "Unknown action '\(action)'. Use 'rewind', 'start', 'stop', or 'status'."
        }
    }
}
