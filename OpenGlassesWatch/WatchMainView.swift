import SwiftUI
import WatchKit

struct WatchMainView: View {
    @StateObject private var connectivity = WatchConnectivityService()
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Connection + battery status
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectivity.isReachable ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(connectivity.isReachable
                         ? (connectivity.isConnected ? "Glasses Connected" : "iPhone Connected")
                         : "iPhone Not Reachable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let battery = connectivity.batteryLevel, battery > 0 {
                        Text("\(battery)%")
                            .font(.caption2)
                            .foregroundStyle(battery < 20 ? .red : .secondary)
                    }
                }

                // Persona agent buttons (from app context)
                if !connectivity.personas.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(connectivity.personas, id: \.id) { persona in
                            personaButton(persona)
                        }
                    }

                    Divider()
                }

                // Fallback generic actions
                VStack(spacing: 8) {
                    actionButton(label: "Ask", icon: "mic.fill", command: "ask")
                    actionButton(label: "Photo", icon: "camera.fill", command: "photo")
                }

                // Response
                if !connectivity.lastResponse.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Response")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(connectivity.lastResponse)
                            .font(.caption)
                            .lineLimit(6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle("OpenGlasses")
    }

    @ViewBuilder
    private func personaButton(_ persona: WatchConnectivityService.PersonaInfo) -> some View {
        Button {
            WKInterfaceDevice.current().play(.start)
            errorMessage = nil
            connectivity.sendCommand("persona", extra: ["persona_id": persona.id]) { error in
                if let error {
                    errorMessage = error
                    WKInterfaceDevice.current().play(.failure)
                } else {
                    WKInterfaceDevice.current().play(.success)
                }
            }
        } label: {
            HStack {
                Image(systemName: "person.fill")
                    .font(.body)
                    .foregroundStyle(.cyan)
                Text(persona.name)
                    .font(.body)
                Spacer()
                if connectivity.isProcessing {
                    ProgressView()
                }
            }
            .padding(.vertical, 8)
        }
        .disabled(!connectivity.isReachable || connectivity.isProcessing)
    }

    @ViewBuilder
    private func actionButton(label: String, icon: String, command: String) -> some View {
        Button {
            WKInterfaceDevice.current().play(.start)
            errorMessage = nil
            connectivity.sendCommand(command) { error in
                if let error {
                    errorMessage = error
                    WKInterfaceDevice.current().play(.failure)
                } else {
                    WKInterfaceDevice.current().play(.success)
                }
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .font(.body)
                Text(label)
                    .font(.body)
                Spacer()
                if connectivity.isProcessing {
                    ProgressView()
                }
            }
            .padding(.vertical, 8)
        }
        .disabled(!connectivity.isReachable || connectivity.isProcessing)
    }
}
