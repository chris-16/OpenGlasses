import Foundation
import WatchConnectivity

/// iPhone-side WatchConnectivity manager. Receives commands from the Watch app
/// and dispatches them to AppState for execution.
@MainActor
class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    weak var appState: AppState?

    private var session: WCSession?

    override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            NSLog("[WatchConn] WCSession not supported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
        NSLog("[WatchConn] Session activated")
    }

    /// Send current app status to the Watch for display.
    func sendStatusUpdate() {
        guard let session, session.isReachable else { return }
        guard let appState else { return }

        let context: [String: Any] = [
            "status": statusString(),
            "isConnected": appState.isConnected,
            "isProcessing": appState.isProcessing,
            "isListening": appState.isListening,
            "lastResponse": String(appState.lastResponse.prefix(200)),
            "deviceName": appState.glassesService.deviceName ?? "",
            "batteryLevel": appState.glassesService.batteryLevel ?? 0,
            "personas": Config.enabledPersonas.prefix(3).map { ["id": $0.id, "name": $0.name] }
        ]

        // Use application context for persistent state
        try? session.updateApplicationContext(context)
    }

    private func statusString() -> String {
        guard let appState else { return "idle" }
        if appState.isListening { return "listening" }
        if appState.isProcessing { return "processing" }
        if appState.speechService.isSpeaking { return "speaking" }
        return "idle"
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        NSLog("[WatchConn] Activation: %@ (error: %@)",
              String(describing: activationState),
              error?.localizedDescription ?? "none")
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        NSLog("[WatchConn] Session became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        NSLog("[WatchConn] Session deactivated")
        session.activate()
    }

    /// Handle real-time messages from the Watch with reply handler.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard let command = message["command"] as? String else {
            replyHandler(["error": "No command specified"])
            return
        }

        NSLog("[WatchConn] Received command: %@", command)

        Task { @MainActor in
            guard let appState = self.appState else {
                replyHandler(["error": "App not ready"])
                return
            }

            switch command {
            case "ask":
                // Trigger wake word flow — start listening
                appState.wakeWordService.stopListening()
                try? await Task.sleep(nanoseconds: 100_000_000)
                await appState.handleWakeWordDetected()
                replyHandler(["status": "listening"])

            case "persona":
                // Activate a specific persona agent and start listening
                if let personaId = message["persona_id"] as? String,
                   let persona = Config.enabledPersonas.first(where: { $0.id == personaId }) {
                    appState.activePersona = persona
                    Config.setActiveModelId(persona.modelId)
                    Config.setActivePresetId(persona.presetId)
                    appState.llmService.refreshActiveModel()
                    appState.wakeWordService.stopListening()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    await appState.handleWakeWordDetected()
                    replyHandler(["status": "listening", "persona": persona.name])
                } else {
                    replyHandler(["error": "Persona not found"])
                }

            case "photo":
                await appState.captureAndAnalyzePhoto()
                replyHandler([
                    "status": "completed",
                    "response": appState.lastResponse
                ])

            case "describe":
                await appState.capturePhotoAndSend(prompt: "Describe what you see in detail.")
                replyHandler([
                    "status": "completed",
                    "response": appState.lastResponse
                ])

            case "status":
                replyHandler([
                    "status": self.statusString(),
                    "isConnected": appState.isConnected,
                    "lastResponse": String(appState.lastResponse.prefix(200))
                ])

            default:
                // Treat as a custom prompt
                if let prompt = message["prompt"] as? String {
                    await appState.capturePhotoAndSend(prompt: prompt)
                    replyHandler([
                        "status": "completed",
                        "response": appState.lastResponse
                    ])
                } else {
                    replyHandler(["error": "Unknown command: \(command)"])
                }
            }

            self.sendStatusUpdate()
        }
    }
}
