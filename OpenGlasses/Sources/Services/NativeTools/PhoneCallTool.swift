import Foundation
import UIKit

/// Initiates a phone call. Automatically resolves contact names to phone numbers.
struct PhoneCallTool: NativeTool {
    let name = "phone_call"
    let description = "Make a phone call. Accepts a phone number OR a contact name — names are automatically looked up in Contacts. If multiple matches are found, returns options."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "number": [
                "type": "string",
                "description": "Phone number (e.g. '+1234567890') or contact name (e.g. 'Mom', 'John'). Names are auto-resolved from Contacts."
            ]
        ],
        "required": ["number"]
    ]

    func execute(args: [String: Any]) async throws -> String {
        guard let input = args["number"] as? String, !input.isEmpty else {
            return "No phone number or contact name provided."
        }

        let phoneNumber: String
        let displayName: String

        if ContactLookupHelper.isPhoneNumber(input) {
            phoneNumber = input
            displayName = input
        } else {
            // It's a name — look up in Contacts
            let matches = ContactLookupHelper.resolve(name: input)

            if matches.isEmpty {
                return "No contact found matching '\(input)'. Please provide a phone number instead, or check the name."
            } else if matches.count == 1 {
                phoneNumber = matches[0].phoneNumber
                displayName = matches[0].name
            } else {
                // Multiple matches
                let uniqueNames = Set(matches.map { $0.name })
                if uniqueNames.count == 1 && matches.count <= 3 {
                    let mobileMatch = matches.first { $0.phoneLabel.lowercased().contains("mobile") || $0.phoneLabel.lowercased().contains("iphone") }
                    let chosen = mobileMatch ?? matches[0]
                    phoneNumber = chosen.phoneNumber
                    displayName = chosen.name
                } else {
                    var options: [String] = []
                    for (i, match) in matches.prefix(5).enumerated() {
                        let label = match.phoneLabel.isEmpty ? "" : " (\(match.phoneLabel))"
                        options.append("\(i + 1). \(match.name)\(label): \(match.phoneNumber)")
                    }
                    return "Multiple contacts match '\(input)'. Which one?\n\(options.joined(separator: "\n"))\nPlease specify the full name or provide the phone number."
                }
            }
        }

        let cleaned = phoneNumber.filter { $0.isNumber || $0 == "+" }

        guard !cleaned.isEmpty,
              let url = URL(string: "tel://\(cleaned)") else {
            return "Invalid phone number: \(phoneNumber)"
        }

        let canOpen = await MainActor.run {
            UIApplication.shared.canOpenURL(url)
        }

        guard canOpen else {
            return "This device can't make phone calls."
        }

        await MainActor.run {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }

        return "Calling \(displayName) (\(phoneNumber))..."
    }
}
