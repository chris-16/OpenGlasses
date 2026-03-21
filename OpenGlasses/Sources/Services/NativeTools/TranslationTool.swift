import Foundation

/// Returns a structured hint for the LLM to translate text inline.
/// The LLM does the actual translation in its response.
struct TranslationTool: NativeTool {
    let name = "translate"
    let description = "Translate text between languages. Works with text from camera captures — can translate foreign signs, menus, labels, and documents seen through the glasses."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "text": [
                "type": "string",
                "description": "The text to translate"
            ],
            "to_language": [
                "type": "string",
                "description": "Target language, e.g. 'Spanish', 'French', 'Japanese'"
            ],
            "from_language": [
                "type": "string",
                "description": "Source language (optional, auto-detected if omitted)"
            ]
        ],
        "required": ["text", "to_language"]
    ]

    func execute(args: [String: Any]) async throws -> String {
        guard let text = args["text"] as? String, !text.isEmpty else {
            return "No text provided to translate."
        }
        guard let toLang = args["to_language"] as? String, !toLang.isEmpty else {
            return "No target language specified."
        }

        let fromLang = args["from_language"] as? String

        if let fromLang {
            return "Translate the following from \(fromLang) to \(toLang): \"\(text)\""
        }
        return "Translate to \(toLang): \"\(text)\""
    }
}
