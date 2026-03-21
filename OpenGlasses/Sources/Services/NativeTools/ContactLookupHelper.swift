import Foundation
import Contacts

/// Shared helper for resolving contact names to phone numbers.
/// Used by SendMessageTool, PhoneCallTool, and ContactsTool.
enum ContactLookupHelper {

    struct ResolvedContact {
        let name: String
        let phoneNumber: String
        let phoneLabel: String
    }

    /// Returns true if the string looks like a phone number (mostly digits/+)
    static func isPhoneNumber(_ str: String) -> Bool {
        let digits = str.filter { $0.isNumber || $0 == "+" }
        // If more than half the characters are digits/+, treat as a number
        return !digits.isEmpty && Double(digits.count) / Double(max(str.count, 1)) > 0.5
    }

    /// Look up a contact by name and return matching contacts with phone numbers.
    /// Returns empty array if no match or contacts access denied.
    static func resolve(name: String) -> [ResolvedContact] {
        let store = CNContactStore()

        // Check access synchronously (already granted by this point in most cases)
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized else { return [] }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]

        let predicate = CNContact.predicateForContacts(matchingName: name)

        guard let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch) else {
            return []
        }

        var results: [ResolvedContact] = []
        for contact in contacts {
            let fullName = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let displayName = fullName.isEmpty ? name : fullName

            for phone in contact.phoneNumbers {
                let label = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: phone.label ?? "")
                results.append(ResolvedContact(
                    name: displayName,
                    phoneNumber: phone.value.stringValue,
                    phoneLabel: label
                ))
            }
        }

        return results
    }
}
