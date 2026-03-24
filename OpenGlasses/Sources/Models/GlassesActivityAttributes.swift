import ActivityKit
import Foundation

/// ActivityKit attributes for the glasses Live Activity (Lock Screen + Dynamic Island).
struct GlassesActivityAttributes: ActivityAttributes {
    /// Static context set when the activity starts.
    var glassesName: String

    /// Dynamic state updated throughout the activity's lifecycle.
    struct ContentState: Codable, Hashable {
        var isConnected: Bool
        var isListening: Bool
        var isSpeaking: Bool
        var isProcessing: Bool
        var lastResponseSnippet: String
        var deviceName: String?
    }
}
