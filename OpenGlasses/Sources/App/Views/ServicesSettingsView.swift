import SwiftUI

/// Sub-settings view for optional service integrations.
/// Accessed via NavigationLink from the main SettingsView.
struct ServicesSettingsView: View {
    @ObservedObject var appState: AppState

    // Text-to-Speech
    @Binding var elevenLabsKeyInput: String
    @Binding var selectedVoice: String
    @Binding var emotionAwareTTSEnabled: Bool

    // Web Search
    @Binding var perplexityKeyInput: String

    // Live Streaming
    @Binding var broadcastPlatform: String
    @Binding var broadcastRTMPURL: String
    @Binding var broadcastStreamKey: String

    // OpenClaw
    @Binding var openClawEnabled: Bool
    @Binding var openClawConnectionMode: OpenClawConnectionMode
    @Binding var openClawLanHost: String
    @Binding var openClawPort: String
    @Binding var openClawTunnelHost: String
    @Binding var openClawGatewayToken: String
    @Binding var openClawTestStatus: String

    // Home Assistant
    @State private var haURL: String = Config.homeAssistantURL
    @State private var haToken: String = Config.homeAssistantToken

    var body: some View {
        Form {
            // MARK: Text-to-Speech
            Section {
                SecureField("API Key", text: $elevenLabsKeyInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Picker("Voice", selection: $selectedVoice) {
                    // Female voices
                    Text("Rachel — calm, American").tag("21m00Tcm4TlvDq8ikWAM")
                    Text("Sarah — soft, American").tag("EXAVITQu4vr4xnSDxMaL")
                    Text("Matilda — warm, American").tag("XrExE9yKIg1WjnnlVkGX")
                    Text("Emily — calm, American").tag("LcfcDJNUP1GQjkzn1xUU")
                    Text("Charlotte — English-Swedish").tag("XB0fDUnXU5powFXDhCwa")
                    Text("Alice — confident, British").tag("Xb7hH8MSUJpSbSDYk0k2")
                    Text("Lily — raspy, British").tag("pFZP5JQG7iQjIQuC4Bku")
                    Text("Dorothy — pleasant, British").tag("ThT5KcBeYPX3keUQqHPh")
                    Text("Serena — pleasant, American").tag("pMsXgVXv3BLzUgSXRplE")
                    Text("Nicole — whisper, American").tag("piTKgcLEGmPE4e6mEKli")
                    // Male voices
                    Text("Brian — deep, American").tag("nPczCjzI2devNBz1zQrb")
                    Text("Adam — deep, American").tag("pNInz6obpgDQGcFmaJgB")
                    Text("Daniel — deep, British").tag("onwK4e9ZLuTAKqWW03F9")
                    Text("George — raspy, British").tag("JBFqnCBsd6RMkjVDRZzb")
                    Text("Chris — casual, American").tag("iP95p4xoKVk53GoZ742B")
                    Text("Charlie — casual, Australian").tag("IKne3meq5aSn9XLyUdCD")
                    Text("James — calm, Australian").tag("ZQe5CZNOzWyzPSCn5a3c")
                    Text("Dave — conversational, British").tag("CYw3kZ02Hs0563khs1Fj")
                    Text("Drew — well-rounded, American").tag("29vD33N1CtxCmqQRPOHJ")
                    Text("Callum — hoarse, American").tag("N2lVS1w4EtoT3dr4eOWO")
                    Text("Bill — strong, American").tag("pqHfZKP75CvOlQylNhV4")
                    Text("Fin — Irish").tag("D38z5RcWu1voky8WS1ja")
                    Text("Liam — American").tag("TX3LPaxmHKxFdv7VOQHJ")
                    Text("Thomas — calm, American").tag("GBv7mTt0atIp3Br8iCZE")
                }

                Toggle("Expressive Voice", isOn: $emotionAwareTTSEnabled)
            } header: {
                Text("Text-to-Speech")
            } footer: {
                if elevenLabsKeyInput.isEmpty {
                    Text("Add an ElevenLabs API key for natural-sounding voices. Without one, the built-in iOS voice is used. Expressive Voice adjusts tone to match content.")
                } else {
                    Text("Expressive Voice adjusts tone to match content — warmer for good news, calmer for instructions.")
                }
            }

            // MARK: Web Search
            Section {
                SecureField("API Key", text: $perplexityKeyInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Web Search")
            } footer: {
                if perplexityKeyInput.isEmpty {
                    Text("Add a Perplexity API key for AI-powered search with cited sources. Without one, DuckDuckGo is used.")
                } else {
                    Text("Web searches use Perplexity AI with cited sources.")
                }
            }

            // MARK: Streaming
            Section {
                Picker("Platform", selection: $broadcastPlatform) {
                    Text("YouTube").tag("youtube")
                    Text("Twitch").tag("twitch")
                    Text("Kick").tag("kick")
                    Text("Custom RTMP").tag("custom")
                }

                TextField("RTMP URL", text: $broadcastRTMPURL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                SecureField("Stream Key", text: $broadcastStreamKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Live Streaming")
            } footer: {
                if broadcastRTMPURL.isEmpty || broadcastStreamKey.isEmpty {
                    Text("Enter both the RTMP URL and stream key from your streaming platform to go live.")
                } else {
                    Text("Stream what your glasses see directly to \(broadcastPlatform.capitalized).")
                }
            }

            // MARK: OpenClaw
            Section {
                Toggle("Enable OpenClaw", isOn: $openClawEnabled)

                if openClawEnabled {
                    SecureField("Gateway Token", text: $openClawGatewayToken)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Picker("Connection", selection: $openClawConnectionMode) {
                        ForEach(OpenClawConnectionMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    if openClawConnectionMode != .tunnel {
                        TextField("LAN Host", text: $openClawLanHost)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        TextField("Port", text: $openClawPort)
                            .keyboardType(.numberPad)
                    }

                    if openClawConnectionMode != .lan {
                        TextField("Tunnel Host", text: $openClawTunnelHost)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    Button("Test Connection") {
                        testOpenClawConnection()
                    }

                    if !openClawTestStatus.isEmpty {
                        HStack {
                            Image(systemName: openClawTestStatus.contains("Connected") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(openClawTestStatus.contains("Connected") ? .green : .red)
                            Text(openClawTestStatus)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("OpenClaw Gateway")
            } footer: {
                Text("OpenClaw runs on your Mac and gives the AI access to 56+ tools — messaging, web search, smart home control, and more.")
            }

            // MARK: Home Assistant
            Section {
                TextField("HA URL (e.g. http://192.168.1.100:8123)", text: $haURL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .onChange(of: haURL) { _, newValue in
                        Config.setHomeAssistantURL(newValue)
                    }

                SecureField("Long-Lived Access Token", text: $haToken)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: haToken) { _, newValue in
                        Config.setHomeAssistantToken(newValue)
                    }
            } header: {
                Text("Home Assistant")
            } footer: {
                Text("Direct REST API control — works alongside or instead of HomeKit. Generate a token in HA → Profile → Security → Long-Lived Access Tokens.")
            }
        }
        .navigationTitle("Services")
    }

    private func testOpenClawConnection() {
        openClawTestStatus = "Testing…"
        Config.setOpenClawEnabled(openClawEnabled)
        Config.setOpenClawConnectionMode(openClawConnectionMode)
        Config.setOpenClawLanHost(openClawLanHost)
        if let port = Int(openClawPort) {
            Config.setOpenClawPort(port)
        }
        Config.setOpenClawTunnelHost(openClawTunnelHost)
        Config.setOpenClawGatewayToken(openClawGatewayToken)

        appState.openClawBridge.clearCachedEndpoint()
        Task {
            await appState.openClawBridge.checkConnection()
            switch appState.openClawBridge.connectionState {
            case .connected:
                let via = appState.openClawBridge.resolvedConnection?.label ?? "unknown"
                openClawTestStatus = "Connected via \(via)"
            case .unreachable(let msg):
                openClawTestStatus = "Unreachable: \(msg)"
            case .notConfigured:
                openClawTestStatus = "Not configured"
            case .checking:
                openClawTestStatus = "Checking…"
            }
        }
    }
}
