import Foundation

/// Evaluates mathematical expressions using NSExpression with input sanitization.
struct CalculatorTool: NativeTool {
    let name = "calculate"
    let description = "Evaluate a mathematical expression. Supports +, -, *, /, parentheses, and decimal numbers."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "expression": [
                "type": "string",
                "description": "The math expression to evaluate, e.g. '(45 * 2) + 100 / 4'"
            ]
        ],
        "required": ["expression"]
    ]

    func execute(args: [String: Any]) async throws -> String {
        guard let expression = args["expression"] as? String, !expression.isEmpty else {
            return "No expression provided."
        }

        // Sanitize: only allow digits, operators, parens, decimal points, spaces
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/() ")
        let sanitized = expression.unicodeScalars.filter { allowed.contains($0) }
        let cleanExpr = String(String.UnicodeScalarView(sanitized))

        guard !cleanExpr.isEmpty else {
            return "Invalid expression. Only numbers and basic operators (+, -, *, /) are supported."
        }

        // Use NSExpression for safe evaluation
        let nsExpr = NSExpression(format: cleanExpr)
        guard let result = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber else {
            return "Couldn't evaluate that expression."
        }

        let doubleResult = result.doubleValue
        // Format nicely: show as integer if it's a whole number
        if doubleResult == doubleResult.rounded() && abs(doubleResult) < 1e15 {
            return "\(expression) = \(Int(doubleResult))"
        }
        return "\(expression) = \(doubleResult)"
    }
}
