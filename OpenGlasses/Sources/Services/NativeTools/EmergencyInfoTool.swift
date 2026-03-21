import Foundation
import CoreLocation

/// Provides emergency information based on the user's current location:
/// local emergency number, nearest hospital search hint, and current GPS coordinates.
final class EmergencyInfoTool: NativeTool, @unchecked Sendable {
    let name = "emergency_info"
    let description = "Get emergency information: local emergency phone number for your country, your exact GPS coordinates, and guidance on finding the nearest hospital."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [:] as [String: Any],
        "required": [] as [String]
    ]

    private let locationService: LocationService

    init(locationService: LocationService) {
        self.locationService = locationService
    }

    // Emergency numbers by ISO country code
    private static let emergencyNumbers: [String: (police: String, ambulance: String, fire: String)] = [
        "US": ("911", "911", "911"),
        "CA": ("911", "911", "911"),
        "GB": ("999", "999", "999"),
        "AU": ("000", "000", "000"),
        "NZ": ("111", "111", "111"),
        "JP": ("110", "119", "119"),
        "KR": ("112", "119", "119"),
        "CN": ("110", "120", "119"),
        "TW": ("110", "119", "119"),
        "IN": ("100", "102", "101"),
        "DE": ("110", "112", "112"),
        "FR": ("17", "15", "18"),
        "IT": ("113", "118", "115"),
        "ES": ("112", "112", "112"),
        "PT": ("112", "112", "112"),
        "NL": ("112", "112", "112"),
        "BE": ("101", "112", "112"),
        "CH": ("117", "144", "118"),
        "AT": ("133", "144", "122"),
        "SE": ("112", "112", "112"),
        "NO": ("112", "113", "110"),
        "DK": ("112", "112", "112"),
        "FI": ("112", "112", "112"),
        "IE": ("999", "999", "999"),
        "MX": ("911", "911", "911"),
        "BR": ("190", "192", "193"),
        "AR": ("101", "107", "100"),
        "TH": ("191", "1669", "199"),
        "VN": ("113", "115", "114"),
        "SG": ("999", "995", "995"),
        "MY": ("999", "999", "994"),
        "ID": ("110", "118", "113"),
        "PH": ("117", "911", "911"),
        "IL": ("100", "101", "102"),
        "AE": ("999", "998", "997"),
        "SA": ("999", "997", "998"),
        "ZA": ("10111", "10177", "10177"),
        "EG": ("122", "123", "180"),
        "TR": ("155", "112", "110"),
        "GR": ("100", "166", "199"),
        "PL": ("997", "999", "998"),
        "CZ": ("158", "155", "150"),
        "HU": ("107", "104", "105"),
        "RO": ("112", "112", "112"),
        "RU": ("102", "103", "101"),
    ]

    func execute(args: [String: Any]) async throws -> String {
        let location = await MainActor.run(body: { locationService.currentLocation })

        var info: [String] = []

        // GPS coordinates
        if let loc = location {
            let lat = String(format: "%.6f", loc.coordinate.latitude)
            let lon = String(format: "%.6f", loc.coordinate.longitude)
            info.append("Your GPS coordinates: \(lat), \(lon)")
        } else {
            info.append("Location unavailable — enable location services for GPS coordinates")
        }

        // Determine country and emergency numbers
        if let loc = location {
            let countryCode = await getCountryCode(for: loc)
            if let code = countryCode, let numbers = Self.emergencyNumbers[code] {
                if numbers.police == numbers.ambulance && numbers.ambulance == numbers.fire {
                    info.append("Emergency number (\(code)): \(numbers.police) (police, ambulance, and fire)")
                } else {
                    info.append("Emergency numbers (\(code)): Police \(numbers.police), Ambulance \(numbers.ambulance), Fire \(numbers.fire)")
                }
            } else {
                info.append("Emergency: Try 112 (international emergency number used in most countries)")
            }
        } else {
            info.append("Emergency: 112 is the international emergency number in most countries. In the US/Canada: 911")
        }

        info.append("To find the nearest hospital, ask me to 'find nearby hospital' and I'll search for one")

        return info.joined(separator: ". ") + "."
    }

    private func getCountryCode(for location: CLLocation) async -> String? {
        await GeocodingHelper.countryCode(for: location)
    }
}
