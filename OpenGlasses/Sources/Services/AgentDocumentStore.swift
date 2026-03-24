import Foundation

/// Manages OpenClaw-compatible agent identity documents.
///
/// The glasses agent follows the OpenClaw document convention:
/// - **soul.md** — Who the agent is: identity, personality, values, goals, communication style
/// - **skills.md** — What the agent can do: capability descriptions, tool usage patterns, learned behaviors
/// - **memory.md** — What the agent knows: persistent facts, user preferences, context
///
/// Documents are stored as plain markdown files in the app's Documents directory,
/// editable by the user, and injected into the system prompt in layers.
/// This makes the glasses agent compatible with OpenClaw's agent architecture.
@MainActor
class AgentDocumentStore: ObservableObject {
    @Published var soul: String = ""
    @Published var skills: String = ""
    @Published var memory: String = ""

    private let documentsDir: URL

    /// Default soul for a fresh install.
    static let defaultSoul = """
    # OpenGlasses Agent

    ## Identity
    I am an AI assistant that lives on Ray-Ban Meta smart glasses. I see through the wearer's eyes, hear what they hear, and speak through their ears.

    ## Personality
    - Concise and natural — I'm spoken aloud, not read on a screen
    - Proactive but not intrusive — I offer help when relevant, stay quiet when not
    - I remember what I learn about my wearer and use that context naturally
    - I adapt my communication style to the situation (formal in meetings, casual with friends)

    ## Values
    - Privacy first — I never share what I see or hear without explicit permission
    - Accuracy — I say "I'm not sure" rather than guess
    - Efficiency — every word I speak costs the wearer's attention

    ## Goals
    - Be genuinely useful in daily life, not just a novelty
    - Learn my wearer's routines, preferences, and needs over time
    - Anticipate needs before being asked when I have enough context
    """

    /// Default skills document.
    static let defaultSkills = """
    # Skills

    ## Vision
    - Describe scenes, read text, identify objects and people
    - Analyze food for nutrition, scan QR/barcodes
    - Provide accessibility descriptions for visually impaired users

    ## Communication
    - Send messages via iMessage, WhatsApp, Telegram, WeChat, email
    - Make phone calls, look up contacts
    - Translate spoken language in real-time

    ## Productivity
    - Manage calendar events, reminders, timers, alarms
    - Take notes tagged with location and time
    - Summarize meetings from ambient audio

    ## Smart Home
    - Control HomeKit devices (lights, locks, thermostats, scenes)
    - Call Home Assistant services directly
    - Run Siri Shortcuts by name

    ## Knowledge
    - Web search with cited sources (Perplexity/DuckDuckGo)
    - Weather, news, currency conversion
    - Remember where things are (object memory with GPS)

    ## Learning
    - Learn new voice-triggered skills at runtime
    - Remember facts about people (social context)
    - Adapt to wearer's preferences over time
    """

    /// Default memory starts empty — the agent builds this over time.
    static let defaultMemory = """
    # Memory

    <!-- This document is updated automatically as the agent learns about you. -->
    <!-- You can also edit it directly to teach the agent facts. -->
    """

    init() {
        documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        loadAll()
    }

    // MARK: - File Paths

    private func path(for document: DocumentType) -> URL {
        documentsDir.appendingPathComponent(document.filename)
    }

    enum DocumentType: String, CaseIterable, Identifiable {
        case soul, skills, memory

        var id: String { rawValue }

        var filename: String {
            switch self {
            case .soul: return "soul.md"
            case .skills: return "skills.md"
            case .memory: return "memory.md"
            }
        }

        var displayName: String {
            switch self {
            case .soul: return "Soul"
            case .skills: return "Skills"
            case .memory: return "Memory"
            }
        }

        var icon: String {
            switch self {
            case .soul: return "heart.text.clipboard"
            case .skills: return "wrench.and.screwdriver"
            case .memory: return "brain.head.profile"
            }
        }

        var description: String {
            switch self {
            case .soul: return "Who the agent is — personality, values, goals"
            case .skills: return "What the agent can do — capabilities and patterns"
            case .memory: return "What the agent knows — facts learned over time"
            }
        }

        var defaultContent: String {
            switch self {
            case .soul: return AgentDocumentStore.defaultSoul
            case .skills: return AgentDocumentStore.defaultSkills
            case .memory: return AgentDocumentStore.defaultMemory
            }
        }
    }

    // MARK: - Load / Save

    func loadAll() {
        soul = load(.soul)
        skills = load(.skills)
        memory = load(.memory)
    }

    private func load(_ type: DocumentType) -> String {
        let url = path(for: type)
        if let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty {
            return content
        }
        // First run: create default
        let defaultContent = type.defaultContent
        try? defaultContent.write(to: url, atomically: true, encoding: .utf8)
        return defaultContent
    }

    func save(_ type: DocumentType, content: String) {
        let url = path(for: type)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        switch type {
        case .soul: soul = content
        case .skills: skills = content
        case .memory: memory = content
        }
        NSLog("[AgentDocs] Saved %@: %d chars", type.filename, content.count)
    }

    func content(for type: DocumentType) -> String {
        switch type {
        case .soul: return soul
        case .skills: return skills
        case .memory: return memory
        }
    }

    // MARK: - System Prompt Integration

    /// Build the agent context block that gets injected into the system prompt.
    /// This is the OpenClaw-compatible agent identity layer.
    func agentContext() -> String? {
        var sections: [String] = []

        if !soul.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(soul)
        }

        if !skills.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(skills)
        }

        if !memory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(memory)
        }

        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n---\n\n")
    }

    // MARK: - Memory Append

    /// Append a fact to the memory document. Called by the AI when it learns something.
    func appendMemory(_ fact: String) {
        let trimmed = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\n- \(trimmed) *(learned \(timestamp))*"
        memory += entry
        save(.memory, content: memory)
        NSLog("[AgentDocs] Memory appended: %@", trimmed)
    }
}
