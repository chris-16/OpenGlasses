import Foundation
import UIKit

/// Copies text to the device clipboard so the user can paste it elsewhere.
struct ClipboardTool: NativeTool {
    let name = "copy_to_clipboard"
    let description = "Copy text to the device clipboard. Useful after reading/translating text from a photo, getting a result, or any time the user says 'copy that'."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "text": [
                "type": "string",
                "description": "The text to copy to the clipboard"
            ]
        ],
        "required": ["text"]
    ]

    func execute(args: [String: Any]) async throws -> String {
        guard let text = args["text"] as? String, !text.isEmpty else {
            return "No text provided to copy."
        }

        await MainActor.run {
            UIPasteboard.general.string = text
        }

        let preview = text.count > 60 ? String(text.prefix(60)) + "..." : text
        return "Copied to clipboard: \(preview)"
    }
}
