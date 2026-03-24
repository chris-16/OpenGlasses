import Foundation

/// Native tool for analyzing food nutrition from a photo.
/// Returns a specialized prompt that instructs the LLM to analyze food
/// when a photo is captured. Works with the existing vision pipeline.
struct FoodAnalysisTool: NativeTool {
    var name: String { "analyze_food" }

    var description: String {
        "Analyze food in the current view for nutrition information. Estimates calories, protein, fat, carbs, and provides health suggestions. Use when the user asks about food nutrition, calories, or 'is this healthy'. Requires a photo to be captured first."
    }

    var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "detail_level": [
                    "type": "string",
                    "description": "Level of detail: 'quick' for just calories/macros, 'detailed' for full breakdown with health score",
                    "enum": ["quick", "detailed"]
                ]
            ]
        ]
    }

    func execute(args: [String: Any]) async throws -> String {
        let detailLevel = (args["detail_level"] as? String) ?? "detailed"

        if detailLevel == "quick" {
            return "I need to see the food to analyze it. Please take a photo and I'll estimate the calories and macros. Say 'take a photo' or 'what's this' while looking at the food."
        } else {
            return "I need to see the food to analyze it. Please take a photo and I'll provide a detailed nutrition breakdown including calories, protein, fat, carbs, fiber, a health score, and dietary suggestions. Say 'take a photo' while looking at the food."
        }
    }
}
