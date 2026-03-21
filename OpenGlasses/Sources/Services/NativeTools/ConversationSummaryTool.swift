import Foundation

/// Summarizes the current conversation or generates action items from it.
/// Uses the ConversationStore to access message history and the LLM to generate summaries.
struct ConversationSummaryTool: NativeTool {
    let name = "summarize_conversation"
    let description = "Summarize the current conversation, extract action items and to-dos, or recap what was discussed. Useful after long conversations or meetings."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "mode": [
                "type": "string",
                "description": "What to generate: 'summary' for a brief recap, 'action_items' for extracted to-dos, 'both' for summary + action items. Default: 'both'"
            ]
        ],
        "required": []
    ]

    /// Reference to the conversation store for accessing message history
    weak var conversationStore: ConversationStore?

    init(conversationStore: ConversationStore) {
        self.conversationStore = conversationStore
    }

    func execute(args: [String: Any]) async throws -> String {
        let mode = (args["mode"] as? String)?.lowercased() ?? "both"

        guard let store = conversationStore else {
            return "Conversation store not available."
        }

        guard let threadId = await MainActor.run(body: { store.activeThreadId }),
              let thread = await MainActor.run(body: { store.threads.first(where: { $0.id == threadId }) }) else {
            return "No active conversation to summarize."
        }

        let messages = thread.messages
        guard messages.count >= 2 else {
            return "The conversation is too short to summarize. Keep chatting and ask me to summarize later."
        }

        // Build a transcript for the LLM to summarize
        var transcript = ""
        for msg in messages {
            let role = msg.role == "user" ? "User" : "Assistant"
            transcript += "\(role): \(msg.content)\n"
        }

        // Truncate if very long (keep last ~3000 chars to stay within reason)
        if transcript.count > 3000 {
            transcript = "...(earlier messages omitted)...\n" + String(transcript.suffix(3000))
        }

        let messageCount = messages.count
        let userMessages = messages.filter { $0.role == "user" }.count
        let duration: String
        if let first = messages.first, let last = messages.last {
            let interval = last.timestamp.timeIntervalSince(first.timestamp)
            let minutes = Int(interval / 60)
            duration = minutes < 1 ? "less than a minute" : "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            duration = "unknown"
        }

        var result = "Conversation: \(messageCount) messages (\(userMessages) from you) over \(duration).\n\n"

        switch mode {
        case "action_items":
            result += "ACTION ITEMS extracted from conversation:\n"
            result += extractActionItems(from: messages)
        case "summary":
            result += "SUMMARY:\n"
            result += generateSummary(from: messages)
        default: // "both"
            result += "SUMMARY:\n"
            result += generateSummary(from: messages)
            result += "\n\nACTION ITEMS:\n"
            result += extractActionItems(from: messages)
        }

        return result
    }

    /// Generate a local summary from message content (no LLM call needed — the LLM receiving this will speak it)
    private func generateSummary(from messages: [ConversationMessage]) -> String {
        // Extract key topics discussed — look at user messages for topics
        let userTopics = messages
            .filter { $0.role == "user" }
            .map { $0.content }

        if userTopics.isEmpty {
            return "No user messages found to summarize."
        }

        // Return the topics so the LLM can formulate a natural spoken summary
        var summary = "Topics discussed: "
        summary += userTopics.prefix(10).enumerated().map { (i, topic) in
            let truncated = String(topic.prefix(80))
            return "\(i + 1). \(truncated)\(topic.count > 80 ? "..." : "")"
        }.joined(separator: "; ")

        return summary + "\n\nPlease provide a natural, conversational summary of these topics to the user."
    }

    /// Extract action items — look for commitments, tasks, reminders mentioned
    private func extractActionItems(from messages: [ConversationMessage]) -> String {
        let actionKeywords = ["remind", "remember", "need to", "have to", "should", "will do", "don't forget",
                              "make sure", "schedule", "set up", "follow up", "call", "email", "send", "buy",
                              "pick up", "todo", "to-do", "task", "deadline", "appointment"]

        var actionMessages: [String] = []
        for msg in messages {
            let lower = msg.content.lowercased()
            if actionKeywords.contains(where: { lower.contains($0) }) {
                let truncated = String(msg.content.prefix(120))
                let role = msg.role == "user" ? "You said" : "I mentioned"
                actionMessages.append("- \(role): \(truncated)\(msg.content.count > 120 ? "..." : "")")
            }
        }

        if actionMessages.isEmpty {
            return "No clear action items found in this conversation."
        }

        return actionMessages.joined(separator: "\n") +
            "\n\nPlease review these and present the action items clearly to the user."
    }
}
