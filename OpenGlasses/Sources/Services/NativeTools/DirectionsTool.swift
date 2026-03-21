import Foundation
import UIKit

/// Opens Apple Maps or Google Maps with directions to a destination.
struct DirectionsTool: NativeTool {
    let name = "get_directions"
    let description = "Get directions to a destination. Opens Apple Maps or Google Maps with turn-by-turn navigation. User can specify which map app to use."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "destination": [
                "type": "string",
                "description": "The destination address or place name"
            ],
            "mode": [
                "type": "string",
                "description": "Travel mode: 'driving', 'walking', or 'transit'. Defaults to driving."
            ],
            "app": [
                "type": "string",
                "description": "Map app to use: 'apple' or 'google'. Defaults to apple."
            ]
        ],
        "required": ["destination"]
    ]

    func execute(args: [String: Any]) async throws -> String {
        guard let destination = args["destination"] as? String, !destination.isEmpty else {
            return "No destination provided."
        }

        let mode = args["mode"] as? String ?? "driving"
        let app = (args["app"] as? String ?? "apple").lowercased()

        guard let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return "Couldn't encode destination: \(destination)."
        }

        let url: URL?
        let appName: String

        if app == "google" || app == "google maps" {
            // Google Maps URL scheme
            let googleMode: String
            switch mode.lowercased() {
            case "walking", "walk": googleMode = "walking"
            case "transit", "public transport": googleMode = "transit"
            default: googleMode = "driving"
            }
            // Try Google Maps app first, fall back to web
            let googleAppURL = URL(string: "comgooglemaps://?daddr=\(encoded)&directionsmode=\(googleMode)")
            let canOpenGoogle = await MainActor.run {
                googleAppURL != nil && UIApplication.shared.canOpenURL(googleAppURL!)
            }
            if canOpenGoogle {
                url = googleAppURL
            } else {
                // Fall back to Google Maps web
                url = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(encoded)&travelmode=\(googleMode)")
            }
            appName = "Google Maps"
        } else {
            // Apple Maps
            let dirFlag: String
            switch mode.lowercased() {
            case "walking", "walk": dirFlag = "w"
            case "transit", "public transport": dirFlag = "r"
            default: dirFlag = "d"
            }
            url = URL(string: "maps://?daddr=\(encoded)&dirflg=\(dirFlag)")
            appName = "Apple Maps"
        }

        guard let openURL = url else {
            return "Couldn't build directions URL for \(destination)."
        }

        await MainActor.run {
            UIApplication.shared.open(openURL, options: [:], completionHandler: nil)
        }

        let modeLabel: String
        switch mode.lowercased() {
        case "walking", "walk": modeLabel = "walking"
        case "transit", "public transport": modeLabel = "transit"
        default: modeLabel = "driving"
        }

        return "Opening \(modeLabel) directions to \(destination) in \(appName)..."
    }
}
