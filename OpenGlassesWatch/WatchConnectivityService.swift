import Foundation
import WatchConnectivity

/// Watch-side WatchConnectivity service. Sends commands to the iPhone app
/// and receives status updates.
class WatchConnectivityService: NSObject, ObservableObject, WCSessionDelegate {
    @Published var isReachable = false
    @Published var isConnected = false
    @Published var isProcessing = false
    @Published var lastResponse = ""
    @Published var status = "idle"
    @Published var deviceName = ""

    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    // MARK: - Send Commands

    func sendCommand(_ command: String, completion: @escaping (String?) -> Void) {
        guard WCSession.default.isReachable else {
            completion("iPhone not reachable")
            return
        }

        isProcessing = true
        WCSession.default.sendMessage(["command": command], replyHandler: { [weak self] reply in
            DispatchQueue.main.async {
                self?.isProcessing = false
                if let response = reply["response"] as? String {
                    self?.lastResponse = response
                    completion(nil)
                } else if let error = reply["error"] as? String {
                    completion(error)
                } else if let status = reply["status"] as? String {
                    self?.status = status
                    completion(nil)
                }
            }
        }, errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.isProcessing = false
                completion(error.localizedDescription)
            }
        })
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    /// Receive application context updates from iPhone.
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            if let connected = applicationContext["isConnected"] as? Bool {
                self.isConnected = connected
            }
            if let status = applicationContext["status"] as? String {
                self.status = status
            }
            if let response = applicationContext["lastResponse"] as? String {
                self.lastResponse = response
            }
            if let name = applicationContext["deviceName"] as? String {
                self.deviceName = name
            }
        }
    }
}
