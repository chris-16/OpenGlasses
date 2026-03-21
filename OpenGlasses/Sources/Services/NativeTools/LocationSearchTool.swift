import Foundation
import MapKit

/// Searches for nearby places (restaurants, cafes, pharmacies, etc.) using Apple's MapKit.
final class LocationSearchTool: NativeTool, @unchecked Sendable {
    let name = "find_nearby"
    let description = "Find nearby places like restaurants, cafes, gas stations, pharmacies, ATMs, etc. Uses the user's current location."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "query": [
                "type": "string",
                "description": "What to search for, e.g. 'coffee shop', 'pharmacy', 'gas station', 'Italian restaurant'"
            ],
            "limit": [
                "type": "integer",
                "description": "Maximum number of results to return. Defaults to 5."
            ]
        ],
        "required": ["query"]
    ]

    private let locationService: LocationService

    init(locationService: LocationService) {
        self.locationService = locationService
    }

    func execute(args: [String: Any]) async throws -> String {
        guard let query = args["query"] as? String, !query.isEmpty else {
            return "No search query provided."
        }

        let limit = (args["limit"] as? Int) ?? 5

        // Get current location
        guard let location = await MainActor.run(body: { locationService.currentLocation }) else {
            return "I don't have your current location. Make sure location services are enabled."
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()

            let items = Array(response.mapItems.prefix(limit))

            guard !items.isEmpty else {
                return "No results found for '\(query)' near your location."
            }

            var results: [String] = []
            for item in items {
                let name = item.name ?? "Unknown"
                var detail = name

                // Distance & address
                let (itemLoc, address) = GeocodingHelper.locationAndAddress(from: item)
                if let itemLoc {
                    let distance = location.distance(from: itemLoc)
                    if distance < 1000 {
                        detail += String(format: " (%.0f m away)", distance)
                    } else {
                        detail += String(format: " (%.1f km away)", distance / 1000)
                    }
                }
                if let address {
                    detail += " at \(address)"
                }

                results.append(detail)
            }

            return "Found \(items.count) result\(items.count == 1 ? "" : "s") for '\(query)': \(results.joined(separator: ". "))."
        } catch {
            return "Search failed: \(error.localizedDescription)"
        }
    }
}
