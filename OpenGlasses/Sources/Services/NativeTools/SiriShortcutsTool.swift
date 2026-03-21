import Foundation
import Intents
import UIKit

/// Runs Siri Shortcuts (Apple Shortcuts app) by name.
/// Allows the user to trigger any shortcut they've created hands-free.
struct SiriShortcutsTool: NativeTool {
    let name = "run_shortcut"
    let description = "Run an Apple Shortcut by name. Triggers shortcuts from the Shortcuts app. Great for custom automations like 'start focus mode', 'log water', or any shortcut the user has created."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "shortcut_name": [
                "type": "string",
                "description": "The name of the Shortcut to run (e.g. 'Start Focus', 'Log Water', 'Morning Routine')"
            ],
            "input": [
                "type": "string",
                "description": "Optional text input to pass to the shortcut"
            ]
        ],
        "required": ["shortcut_name"]
    ]

    func execute(args: [String: Any]) async throws -> String {
        guard let shortcutName = args["shortcut_name"] as? String, !shortcutName.isEmpty else {
            return "No shortcut name provided."
        }

        let input = args["input"] as? String

        // Build the shortcuts:// URL to run a shortcut
        var urlString = "shortcuts://run-shortcut?name=\(shortcutName)"
        if let input = input {
            urlString += "&input=text&text=\(input)"
        }

        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded) else {
            return "Couldn't build URL for shortcut '\(shortcutName)'."
        }

        let canOpen = await MainActor.run {
            UIApplication.shared.canOpenURL(url)
        }

        guard canOpen else {
            return "The Shortcuts app doesn't appear to be available. Make sure it's installed."
        }

        await MainActor.run {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }

        return "Running shortcut '\(shortcutName)'..."
    }
}
