import SwiftUI
import WatchKit

struct WatchMainView: View {
    @StateObject private var connectivity = WatchConnectivityService()
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Connection status
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectivity.isReachable ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(connectivity.isReachable
                         ? (connectivity.isConnected ? "Glasses Connected" : "iPhone Connected")
                         : "iPhone Not Reachable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Quick action buttons
                VStack(spacing: 10) {
                    actionButton(label: "Ask", icon: "mic.fill", command: "ask")
                    actionButton(label: "Photo", icon: "camera.fill", command: "photo")
                    actionButton(label: "Describe", icon: "eye", command: "describe")
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

                // Error
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
