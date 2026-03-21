import Foundation

/// Protocol for all built-in tools that run on-device without external APIs.
protocol NativeTool {
    var name: String { get }
    var description: String { get }
    var parametersSchema: [String: Any] { get }
    func execute(args: [String: Any]) async throws -> String
}
