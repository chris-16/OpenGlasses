import Foundation

/// AI-managed persistent user memory.
///
/// The AI can store facts about the user (preferences, names, locations, routines)
/// that persist across sessions. These are injected into the system prompt so the
/// AI can reference them naturally.
///
/// Storage format: simple key-value pairs in a JSON file.
/// The AI manages this via structured commands in its responses (parsed by the caller).
///
/// Example memories:
///   "name" → "Greig"
///   "coffee" → "Flat white, no sugar"
///   "partner" → "Sarah"
///   "home_city" → "Melbourne"
@MainActor
class UserMemoryStore: ObservableObject {
    @Published var memories: [String: String] = [:]

    private let storageURL: URL
    private let maxMemories = 100

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = docs.appendingPathComponent("user_memories.json")
        load()
    }

    // MARK: - CRUD

    /// Store or update a memory. Key is lowercased and trimmed.
    func remember(_ key: String, value: String) {
        let normalizedKey = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty, !value.isEmpty else { return }
        memories[normalizedKey] = value
        trimIfNeeded()
        save()
        NSLog("[Memory] Stored: %@ = %@", normalizedKey, value)
    }

    /// Forget a specific memory.
    func forget(_ key: String) {
        let normalizedKey = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if memories.removeValue(forKey: normalizedKey) != nil {
            save()
            NSLog("[Memory] Forgot: %@", normalizedKey)
        }
    }

    /// Recall a specific memory.
    func recall(_ key: String) -> String? {
        let normalizedKey = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return memories[normalizedKey]
    }

    /// Clear all memories.
    func clearAll() {
        memories.removeAll()
        save()
        NSLog("[Memory] Cleared all memories")
    }

    // MARK: - System Prompt Injection

    /// Generate a memory context string to inject into the system prompt.
    /// Returns nil if no memories are stored.
    func systemPromptContext() -> String? {
        guard !memories.isEmpty else { return nil }

        var lines: [String] = []
        for (key, value) in memories.sorted(by: { $0.key < $1.key }) {
            lines.append("- \(key): \(value)")
        }

        return """
        USER MEMORY (facts you've learned about this user — reference naturally, don't list them):
        \(lines.joined(separator: "\n"))
        """
    }

    // MARK: - AI Response Parsing

    /// Parse memory commands from an AI response.
    /// Commands are inline tags: [REMEMBER: key = value] and [FORGET: key]
    /// Returns the response with commands stripped out.
    func parseAndExecuteCommands(in response: String) -> String {
        var cleaned = response

        // Parse [REMEMBER: key = value] commands
        let rememberPattern = #"\[REMEMBER:\s*(.+?)\s*=\s*(.+?)\]"#
        if let regex = try? NSRegularExpression(pattern: rememberPattern, options: []) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            for match in matches.reversed() {
                if let keyRange = Range(match.range(at: 1), in: response),
                   let valueRange = Range(match.range(at: 2), in: response) {
                    let key = String(response[keyRange])
                    let value = String(response[valueRange])
                    remember(key, value: value)
                }
                if let fullRange = Range(match.range, in: cleaned) {
                    cleaned.removeSubrange(fullRange)
                }
            }
        }

        // Parse [FORGET: key] commands
        let forgetPattern = #"\[FORGET:\s*(.+?)\]"#
        if let regex = try? NSRegularExpression(pattern: forgetPattern, options: []) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            for match in matches.reversed() {
                if let keyRange = Range(match.range(at: 1), in: response) {
                    let key = String(response[keyRange])
                    forget(key)
                }
                if let fullRange = Range(match.range, in: cleaned) {
                    cleaned.removeSubrange(fullRange)
                }
            }
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(memories)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSLog("[Memory] Save failed: %@", error.localizedDescription)
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            memories = try JSONDecoder().decode([String: String].self, from: data)
            NSLog("[Memory] Loaded %d memories", memories.count)
        } catch {
            NSLog("[Memory] Load failed: %@", error.localizedDescription)
        }
    }

    private func trimIfNeeded() {
        guard memories.count > maxMemories else { return }
        // Remove oldest entries (by key alphabetical — simple but stable)
        let sortedKeys = memories.keys.sorted()
        let excess = memories.count - maxMemories
        for key in sortedKeys.prefix(excess) {
            memories.removeValue(forKey: key)
        }
    }
}
