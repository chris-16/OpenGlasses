import Foundation
import CoreLocation
import MapKit

/// Centralizes geocoding using the modern iOS 26 MKGeocodingRequest/MKReverseGeocodingRequest APIs,
/// with CLGeocoder fallback for iOS 17-25.
enum GeocodingHelper {

    /// Result type for reverse geocoding — normalizes across API versions.
    struct PlaceInfo {
        let locality: String?
        let administrativeArea: String?
        let isoCountryCode: String?
        let thoroughfare: String?
        let subThoroughfare: String?
        let fullAddress: String?
        let location: CLLocation?

        /// Formatted short address (e.g. "123 Main St")
        var streetAddress: String? {
            guard let street = thoroughfare else { return nil }
            let number = subThoroughfare ?? ""
            return "\(number) \(street)".trimmingCharacters(in: .whitespaces)
        }

        /// City + state (e.g. "San Francisco, CA")
        var cityState: String? {
            let parts = [locality, administrativeArea].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
    }

    // MARK: - Reverse Geocoding

    /// Reverse geocode a location to place info.
    static func reverseGeocode(_ location: CLLocation) async -> PlaceInfo? {
        if #available(iOS 26, *) {
            return await reverseGeocodeModern(location)
        } else {
            return await reverseGeocodeLegacy(location)
        }
    }

    /// Reverse geocode coordinates to place info.
    static func reverseGeocode(latitude: Double, longitude: Double) async -> PlaceInfo? {
        await reverseGeocode(CLLocation(latitude: latitude, longitude: longitude))
    }

    // MARK: - Forward Geocoding

    /// Forward geocode an address string to a location.
    static func geocodeAddress(_ address: String) async -> CLLocation? {
        if #available(iOS 26, *) {
            return await geocodeAddressModern(address)
        } else {
            return await geocodeAddressLegacy(address)
        }
    }

    // MARK: - Map Item Helpers

    /// Extract location and address from an MKMapItem.
    static func locationAndAddress(from item: MKMapItem) -> (location: CLLocation?, address: String?) {
        if #available(iOS 26, *) {
            let loc = item.location
            let addr = item.address?.shortAddress ?? item.address?.fullAddress
            return (loc, addr)
        } else {
            return locationAndAddressLegacy(from: item)
        }
    }

    /// Get just the country code for a location (needs CLGeocoder even on iOS 26
    /// since MKReverseGeocodingRequest doesn't expose country codes).
    static func countryCode(for location: CLLocation) async -> String? {
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            return placemarks.first?.isoCountryCode
        } catch {
            return nil
        }
    }

    // MARK: - iOS 26+ (Modern)

    @available(iOS 26, *)
    private static func reverseGeocodeModern(_ location: CLLocation) async -> PlaceInfo? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        do {
            let items = try await request.mapItems
            guard let item = items.first else { return nil }
            let addr = item.address
            // MKAddress on iOS 26 has fullAddress and shortAddress
            // MKMapItem still has .placemark for backward compat but we avoid it
            return PlaceInfo(
                locality: nil,  // MKAddress doesn't expose individual components
                administrativeArea: nil,
                isoCountryCode: nil,
                thoroughfare: nil,
                subThoroughfare: nil,
                fullAddress: addr?.fullAddress,
                location: item.location
            )
        } catch {
            return nil
        }
    }

    @available(iOS 26, *)
    private static func geocodeAddressModern(_ address: String) async -> CLLocation? {
        guard let request = MKGeocodingRequest(addressString: address) else { return nil }
        do {
            let items = try await request.mapItems
            return items.first?.location
        } catch {
            return nil
        }
    }

    // MARK: - iOS 17-25 (Legacy)

    private static func reverseGeocodeLegacy(_ location: CLLocation) async -> PlaceInfo? {
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            guard let p = placemarks.first else { return nil }
            return PlaceInfo(
                locality: p.locality,
                administrativeArea: p.administrativeArea,
                isoCountryCode: p.isoCountryCode,
                thoroughfare: p.thoroughfare,
                subThoroughfare: p.subThoroughfare,
                fullAddress: [p.subThoroughfare, p.thoroughfare, p.locality, p.administrativeArea]
                    .compactMap { $0 }.joined(separator: " "),
                location: p.location
            )
        } catch {
            return nil
        }
    }

    private static func geocodeAddressLegacy(_ address: String) async -> CLLocation? {
        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(address)
            return placemarks.first?.location
        } catch {
            return nil
        }
    }

    private static func locationAndAddressLegacy(from item: MKMapItem) -> (location: CLLocation?, address: String?) {
        let location = item.placemark.location
        let thoroughfare = item.placemark.thoroughfare
        let subThoroughfare = item.placemark.subThoroughfare
        var address: String? = nil
        if let street = thoroughfare {
            let number = subThoroughfare ?? ""
            address = "\(number) \(street)".trimmingCharacters(in: .whitespaces)
        }
        return (location, address)
    }
}
