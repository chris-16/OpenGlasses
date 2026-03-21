import Foundation

/// A single message in a conversation thread.
struct ConversationMessage: Codable, Identifiable {
    let id: String
    let role: String          // "user", "assistant", "system"
    let content: String
    let imageAttached: Bool
    let timestamp: Date

    init(role: String, content: String, imageAttached: Bool = false) {
        self.id = UUID().uuidString
        self.role = role
        self.content = content
        self.imageAttached = imageAttached
        self.timestamp = Date()
    }
}

/// A conversation thread with metadata.
struct ConversationThread: Codable, Identifiable {
    let id: String
    var title: String
    var messages: [ConversationMessage]
    let createdAt: Date
    var updatedAt: Date
    var mode: String          // AppMode rawValue

    init(mode: String, title: String = "New Conversation") {
        self.id = UUID().uuidString
        self.title = title
        self.messages = []
        self.createdAt = Date()
        self.updatedAt = Date()
        self.mode = mode
    }
}

/// Persists conversation threads to disk as JSON.
/// Supports saving, loading, resuming, and auto-titling via LLM.
///
/// Usage:
///   - Call `startThread(mode:)` at session start
///   - Call `appendMessage(role:content:)` after each user/assistant turn
///   - Call `endThread()` when the session ends (triggers auto-title)
///   - Call `replayMessages(for:)` to rebuild context on session resume
@MainActor
class ConversationStore: ObservableObject {
    @Published var threads: [ConversationThread] = []
    @Published var activeThreadId: String?

    private let maxThreads = 50
    private let storageURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = docs.appendingPathComponent("conversations.json")
        loadThreads()
    }

    // MARK: - Thread Lifecycle

    /// Start a new conversation thread.
    @discardableResult
    func startThread(mode: String) -> ConversationThread {
        let thread = ConversationThread(mode: mode)
        threads.insert(thread, at: 0)
        activeThreadId = thread.id
        trimOldThreads()
        save()
        NSLog("[ConversationStore] Started thread %@", thread.id)
        return thread
    }

    /// Append a message to the active thread.
    func appendMessage(role: String, content: String, imageAttached: Bool = false) {
        guard let idx = threads.firstIndex(where: { $0.id == activeThreadId }) else { return }
        let msg = ConversationMessage(role: role, content: content, imageAttached: imageAttached)
        threads[idx].messages.append(msg)
        threads[idx].updatedAt = Date()
        save()
    }

    /// End the active thread and auto-generate a title.
    func endThread() {
        guard let idx = threads.firstIndex(where: { $0.id == activeThreadId }) else { return }
        // Generate a title from first user message
        if threads[idx].title == "New Conversation" {
            if let firstUser = threads[idx].messages.first(where: { $0.role == "user" }) {
                threads[idx].title = Self.generateTitle(from: firstUser.content)
            }
        }
        threads[idx].updatedAt = Date()
        save()
        activeThreadId = nil
        NSLog("[ConversationStore] Ended thread")
    }

    /// Resume an existing thread (e.g. after app relaunch).
    func resumeThread(_ threadId: String) -> ConversationThread? {
        guard let thread = threads.first(where: { $0.id == threadId }) else { return nil }
        activeThreadId = threadId
        NSLog("[ConversationStore] Resumed thread %@ (%d messages)", threadId, thread.messages.count)
        return thread
    }

    /// Get messages for replay — returns (role, content) pairs for rebuilding LLM context.
    func replayMessages(for threadId: String) -> [(role: String, content: String)] {
        guard let thread = threads.first(where: { $0.id == threadId }) else { return [] }
        return thread.messages.map { (role: $0.role, content: $0.content) }
    }

    /// Delete a thread.
    func deleteThread(_ threadId: String) {
        threads.removeAll { $0.id == threadId }
        if activeThreadId == threadId { activeThreadId = nil }
        save()
    }

    /// Most recent thread for a given mode.
    func mostRecentThread(for mode: String) -> ConversationThread? {
        return threads.first { $0.mode == mode && !$0.messages.isEmpty }
    }

    // MARK: - Title Generation

    /// Generate a short title from the first user message (local, no LLM needed).
    private static func generateTitle(from text: String) -> String {
        let words = text.split(separator: " ").prefix(6)
        var title = words.joined(separator: " ")
        if text.split(separator: " ").count > 6 {
            title += "…"
        }
        // Capitalize first letter
        if let first = title.first {
            title = first.uppercased() + title.dropFirst()
        }
        return title
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(threads)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSLog("[ConversationStore] Save failed: %@", error.localizedDescription)
        }
    }

    private func loadThreads() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            threads = try JSONDecoder().decode([ConversationThread].self, from: data)
            NSLog("[ConversationStore] Loaded %d threads", threads.count)
        } catch {
            NSLog("[ConversationStore] Load failed: %@", error.localizedDescription)
        }
    }

    private func trimOldThreads() {
        if threads.count > maxThreads {
            threads = Array(threads.prefix(maxThreads))
        }
    }
}
