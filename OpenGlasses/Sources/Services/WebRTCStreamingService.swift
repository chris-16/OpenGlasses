import Foundation
import Combine
import UIKit

/// Lightweight WebRTC-style browser streaming via WebSocket signaling.
/// Converts camera frames to MJPEG and streams them to connected web browsers.
///
/// Architecture:
/// - Runs a local WebSocket relay: phone pushes JPEG frames to the signaling server
/// - A companion web page connects to the same server and displays the stream
/// - Uses a free signaling relay (configurable) so no server setup needed
///
/// For production, this could be upgraded to proper WebRTC with LiveKit or similar.
@MainActor
class WebRTCStreamingService: ObservableObject {
    @Published var isStreaming: Bool = false
    @Published var viewerCount: Int = 0
    @Published var streamURL: String = ""
    @Published var errorMessage: String?

    /// JPEG quality for streamed frames (0.0 - 1.0)
    var jpegQuality: CGFloat = 0.4

    /// Target FPS for the stream
    var targetFPS: Double = 15.0

    private var webSocket: URLSessionWebSocketTask?
    private var frameSubscription: AnyCancellable?
    private var heartbeatTask: Task<Void, Never>?
    private var roomId: String = ""
    private var lastFrameTime: Date = .distantPast

    /// The signaling server URL. Users can set up their own or use a public relay.
    private var signalingURL: String {
        Config.webRTCSignalingURL
    }

    // MARK: - Public API

    /// Start streaming camera frames to the signaling server.
    /// Returns a URL that can be shared with viewers.
    func startStreaming(framePublisher: PassthroughSubject<UIImage, Never>) -> String {
        guard !isStreaming else { return streamURL }

        // Generate a random room ID
        roomId = generateRoomId()
        let viewerURL = "\(Config.webRTCViewerBaseURL)?room=\(roomId)"
        streamURL = viewerURL

        // Connect to signaling server
        connectWebSocket()

        // Subscribe to frame publisher
        let interval = 1.0 / targetFPS
        frameSubscription = framePublisher
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .sink { [weak self] image in
                guard let self = self else { return }
                let now = Date()
                guard now.timeIntervalSince(self.lastFrameTime) >= interval else { return }
                self.lastFrameTime = now
                self.sendFrame(image)
            }

        isStreaming = true
        errorMessage = nil

        // Start heartbeat to maintain connection and track viewers
        startHeartbeat()

        print("📡 WebRTC streaming started: \(viewerURL)")
        return viewerURL
    }

    func stopStreaming() {
        frameSubscription?.cancel()
        frameSubscription = nil

        heartbeatTask?.cancel()
        heartbeatTask = nil

        // Send stop message
        if let ws = webSocket {
            let stopMsg: [String: Any] = ["type": "stream_stop", "room": roomId]
            if let data = try? JSONSerialization.data(withJSONObject: stopMsg),
               let str = String(data: data, encoding: .utf8) {
                ws.send(.string(str)) { _ in }
            }
            ws.cancel(with: .normalClosure, reason: nil)
        }
        webSocket = nil

        isStreaming = false
        viewerCount = 0
        streamURL = ""
        roomId = ""

        print("📡 WebRTC streaming stopped")
    }

    // MARK: - WebSocket Connection

    private func connectWebSocket() {
        guard let url = URL(string: "\(signalingURL)?role=streamer&room=\(roomId)") else {
            errorMessage = "Invalid signaling URL"
            return
        }

        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()

        receiveMessages()

        // Send initial handshake
        let hello: [String: Any] = [
            "type": "stream_start",
            "room": roomId,
            "format": "mjpeg",
            "fps": targetFPS
        ]
        sendJSON(hello)
    }

    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.handleMessage(message)
                    self?.receiveMessages() // Continue listening
                case .failure(let error):
                    print("📡 WebSocket receive error: \(error)")
                    if self?.isStreaming == true {
                        // Attempt reconnect
                        self?.reconnect()
                    }
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { return }

            switch type {
            case "viewer_count":
                viewerCount = json["count"] as? Int ?? 0
            case "viewer_joined":
                viewerCount += 1
                print("📡 Viewer joined (total: \(viewerCount))")
            case "viewer_left":
                viewerCount = max(0, viewerCount - 1)
                print("📡 Viewer left (total: \(viewerCount))")
            case "error":
                errorMessage = json["message"] as? String ?? "Unknown error"
            default:
                break
            }
        case .data:
            break // Binary messages not expected from server
        @unknown default:
            break
        }
    }

    private func reconnect() {
        webSocket?.cancel(with: .abnormalClosure, reason: nil)
        webSocket = nil

        // Wait briefly then reconnect
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if isStreaming {
                connectWebSocket()
            }
        }
    }

    // MARK: - Frame Sending

    private nonisolated func sendFrame(_ image: UIImage) {
        guard let jpegData = image.jpegData(compressionQuality: 0.4) else { return }

        // Base64 encode for WebSocket text transport
        let base64 = jpegData.base64EncodedString()
        let frameMsg: [String: Any] = [
            "type": "frame",
            "data": base64,
            "timestamp": Date().timeIntervalSince1970
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: frameMsg),
              let jsonStr = String(data: jsonData, encoding: .utf8) else { return }

        // Send as binary for efficiency if the frame is large
        if jpegData.count > 50_000 {
            // Send raw binary with a 4-byte header
            var binaryMsg = Data()
            binaryMsg.append(contentsOf: [0x01]) // frame type marker
            binaryMsg.append(jpegData)
            Task { @MainActor [weak self] in
                self?.webSocket?.send(.data(binaryMsg)) { error in
                    if let error = error {
                        print("📡 Frame send error: \(error)")
                    }
                }
            }
        } else {
            Task { @MainActor [weak self] in
                self?.webSocket?.send(.string(jsonStr)) { error in
                    if let error = error {
                        print("📡 Frame send error: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask = Task {
            while !Task.isCancelled && isStreaming {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
                let ping: [String: Any] = ["type": "heartbeat", "room": roomId]
                sendJSON(ping)
            }
        }
    }

    // MARK: - Helpers

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        webSocket?.send(.string(str)) { error in
            if let error = error {
                print("📡 WebSocket send error: \(error)")
            }
        }
    }

    private func generateRoomId() -> String {
        // 6-character alphanumeric room code
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}
