import Foundation
import CoreMotion

/// Reports step count and walking/running distance for today using CoreMotion.
final class PedometerTool: NativeTool, @unchecked Sendable {
    let name = "step_count"
    let description = "Get today's step count, walking distance, and floors climbed."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [:] as [String: Any],
        "required": [] as [String]
    ]

    private let pedometer = CMPedometer()

    func execute(args: [String: Any]) async throws -> String {
        guard CMPedometer.isStepCountingAvailable() else {
            return "Step counting isn't available on this device."
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())

        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: startOfDay, to: Date()) { data, error in
                if let error {
                    continuation.resume(returning: "Couldn't read step data: \(error.localizedDescription)")
                    return
                }

                guard let data else {
                    continuation.resume(returning: "No step data available for today.")
                    return
                }

                var parts: [String] = []

                let steps = data.numberOfSteps.intValue
                parts.append("\(steps.formatted()) steps")

                if let distance = data.distance?.doubleValue {
                    if distance >= 1000 {
                        parts.append(String(format: "%.1f km walked", distance / 1000))
                    } else {
                        parts.append(String(format: "%.0f meters walked", distance))
                    }
                }

                if let floors = data.floorsAscended?.intValue, floors > 0 {
                    parts.append("\(floors) floor\(floors == 1 ? "" : "s") climbed")
                }

                let result = "Today so far: \(parts.joined(separator: ", "))."
                continuation.resume(returning: result)
            }
        }
    }
}
