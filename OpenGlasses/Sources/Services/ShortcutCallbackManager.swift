import Foundation

/// Manages x-callback-url results from Siri Shortcuts.
/// When a shortcut runs via x-callback-url and finishes, it redirects back
/// to openglasses://shortcut-result with the output. This manager bridges
/// the async gap between the URL open and the callback.
@MainActor
class ShortcutCallbackManager {
    static let shared = ShortcutCallbackManager()

    private var pendingToolName: String?
    private var continuation: CheckedContinuation<String?, Never>?

    /// Mark that we're waiting for a shortcut result.
    func setPending(toolName: String) {
        pendingToolName = toolName
    }

    /// Wait for the shortcut to callback. Returns the output text or nil on timeout.
    func waitForResult(timeout: TimeInterval = 30) async -> String? {
        return await withCheckedContinuation { cont in
            self.continuation = cont

            // Timeout
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let pending = self.continuation {
                    self.continuation = nil
                    self.pendingToolName = nil
                    pending.resume(returning: nil)
                }
            }
        }
    }

    /// Called when the app receives a callback URL from a shortcut.
    /// URL format: openglasses://shortcut-result?output=...
    func handleCallback(url: URL) {
        let host = url.host
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let output = params?.first(where: { $0.name == "output" })?.value
            ?? params?.first(where: { $0.name == "result" })?.value

        switch host {
        case "shortcut-result":
            let result = output ?? "Shortcut completed successfully."
            NSLog("[ShortcutCallback] Result: %@", String(result.prefix(200)))
            continuation?.resume(returning: result)
            continuation = nil
            pendingToolName = nil

        case "shortcut-cancel":
            NSLog("[ShortcutCallback] Cancelled")
            continuation?.resume(returning: "Shortcut was cancelled.")
            continuation = nil
            pendingToolName = nil

        case "shortcut-error":
            let error = output ?? "Shortcut encountered an error."
            NSLog("[ShortcutCallback] Error: %@", error)
            continuation?.resume(returning: "Shortcut error: \(error)")
            continuation = nil
            pendingToolName = nil

        default:
            break
        }
    }
}
