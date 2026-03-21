import Foundation
import UIKit

/// Looks up word definitions using Apple's built-in dictionary (UIReferenceLibraryViewController).
struct WordDefinitionTool: NativeTool {
    let name = "define_word"
    let description = "Look up the definition of a word or phrase. Uses the device's built-in dictionary."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "word": [
                "type": "string",
                "description": "The word or phrase to define"
            ]
        ],
        "required": ["word"]
    ]

    func execute(args: [String: Any]) async throws -> String {
        guard let word = args["word"] as? String, !word.isEmpty else {
            return "No word provided to define."
        }

        // Check if the system dictionary has a definition
        let hasDefinition = await MainActor.run {
            UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: word)
        }

        if hasDefinition {
            // We can't extract the text from the dictionary, so we let the LLM know
            // the word exists and provide what we can
            return "The word '\(word)' is in the dictionary. Since I'm a voice assistant, I'll define it from my knowledge rather than displaying the dictionary entry. The LLM should provide the definition directly."
        } else {
            return "'\(word)' was not found in the device dictionary. It may be a proper noun, slang, or technical term. I'll try to define it from my general knowledge."
        }
    }
}
