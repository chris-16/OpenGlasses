import SwiftUI

/// Bottom control bar with circular action buttons spanning the full width.
/// Layout: [Settings] [Camera] [🎤 Hero] [Preview] [Model] [Persona]
struct BottomControlBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var session: GeminiLiveSessionManager
    @ObservedObject var openAISession: OpenAIRealtimeSessionManager

    /// Sheet bindings passed down from MainView
    @Binding var showSettings: Bool
    @Binding var showModelPicker: Bool
    @Binding var showPreview: Bool
    @Binding var showPersonaPicker: Bool

    private var isRealtime: Bool { appState.currentMode.isRealtime }
    private var isGemini: Bool { appState.currentMode == .geminiLive }
    private var isOpenAI: Bool { appState.currentMode == .openaiRealtime }

    private var realtimeSessionActive: Bool {
        isGemini ? session.isActive : (isOpenAI ? openAISession.isActive : false)
    }

    // MARK: - Slot visibility

    private var previewVisible: Bool { appState.isConnected }

    /// Photo capture disabled for local text-only models (no vision encoder).
    private var photoDisabledForLocalModel: Bool {
        guard let model = Config.activeModel, model.llmProvider == .local else { return false }
        return !model.visionEnabled
    }
    private var modeVisible: Bool {
        switch appState.currentMode {
        case .geminiLive, .openaiRealtime: return true
        case .direct: return Config.isGeminiLiveConfigured
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Slot 1: Settings
            CircleButton(icon: "gearshape", size: 38, label: "Settings") {
                showSettings = true
            }
            .frame(maxWidth: .infinity)

            // Slot 2: Camera / Connect
            cameraButton
                .frame(maxWidth: .infinity)

            // Slot 3: Hero — mic or session toggle (largest)
            heroButton
                .frame(maxWidth: .infinity)

            // Slot 4: Preview (dimmed when no glasses)
            CircleButton(
                icon: "eye",
                size: 38,
                isActive: appState.videoRecorder.isRecording,
                isDisabled: !previewVisible,
                label: previewVisible ? "Live Preview" : "No glasses"
            ) {
                if previewVisible { showPreview = true }
            }
            .opacity(previewVisible ? 1 : 0.3)
            .frame(maxWidth: .infinity)

            // Slot 5: Model picker
            CircleButton(icon: "brain", size: 38, label: "Switch Model") {
                showModelPicker = true
            }
            .frame(maxWidth: .infinity)

            // Slot 6: Persona
            personaButton
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.5), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()
        )
    }

    // MARK: - Slot Builders

    @ViewBuilder
    private var cameraButton: some View {
        if !appState.isConnected {
            CircleButton(
                icon: "camera.fill",
                size: 38,
                label: "Connect Glasses"
            ) {
                Task { await appState.glassesService.connect() }
                appState.errorMessage = "Connecting glasses for camera…"
            }
        } else if isRealtime {
            CircleButton(
                icon: "video.fill",
                size: 38,
                isActive: appState.cameraService.isStreaming,
                isDisabled: !realtimeSessionActive,
                label: appState.cameraService.isStreaming ? "Camera Streaming" : "Start Camera"
            ) {
                if realtimeSessionActive && !appState.cameraService.isStreaming {
                    Task {
                        do {
                            try await appState.cameraService.startStreaming()
                        } catch {
                            appState.errorMessage = "Camera: \(error.localizedDescription)"
                        }
                    }
                }
            }
        } else {
            CircleButton(
                icon: "camera.fill",
                size: 38,
                isActive: appState.cameraService.isCaptureInProgress,
                isDisabled: appState.cameraService.isCaptureInProgress || photoDisabledForLocalModel,
                label: photoDisabledForLocalModel ? "Photos not available (text-only model)" : "Take Photo"
            ) {
                if !photoDisabledForLocalModel {
                    Task { await appState.captureAndAnalyzePhoto() }
                }
            }
        }
    }

    @ViewBuilder
    private var heroButton: some View {
        if isGemini {
            CircleButton(
                icon: session.isActive ? "stop.fill" : "play.fill",
                size: 56,
                isActive: session.isActive,
                label: session.isActive ? "Stop Gemini Session" : "Start Gemini Session"
            ) {
                Task {
                    if session.isActive {
                        session.stopSession()
                    } else {
                        await session.startSession()
                    }
                }
            }
        } else if isOpenAI {
            CircleButton(
                icon: openAISession.isActive ? "stop.fill" : "play.fill",
                size: 56,
                isActive: openAISession.isActive,
                label: openAISession.isActive ? "Stop OpenAI Session" : "Start OpenAI Session"
            ) {
                Task {
                    if openAISession.isActive {
                        openAISession.stopSession()
                    } else {
                        await openAISession.startSession()
                    }
                }
            }
        } else if appState.isProcessing || appState.speechService.isSpeaking {
            // Interrupt: cancel current processing or TTS
            CircleButton(
                icon: "stop.fill",
                size: 56,
                isActive: true,
                label: appState.speechService.isSpeaking ? "Tap to stop" : "Tap to cancel"
            ) {
                appState.cancelCurrentResponse()
            }
        } else {
            CircleButton(
                icon: appState.isListening ? "mic.fill" : "mic",
                size: 56,
                isActive: appState.isListening,
                label: appState.isListening ? "Listening" : "Start Listening"
            ) {
                Task {
                    if appState.isListening {
                        // Tap while listening → cancel and return to wake word
                        await appState.returnToWakeWord()
                    } else {
                        // Tap to start → stop wake word first, then start transcription
                        appState.wakeWordService.stopListening()
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        await appState.handleWakeWordDetected()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var personaButton: some View {
        let activePersona = appState.activePersona
        let personaCount = Config.enabledPersonas.count
        CircleButton(
            icon: "person.2",
            size: 38,
            isActive: activePersona != nil,
            badge: personaCount > 1 ? "\(personaCount)" : nil,
            label: activePersona != nil ? "Active: \(activePersona!.name)" : "Personas"
        ) {
            showPersonaPicker = true
        }
    }

    @ViewBuilder
    private var modeButton: some View {
        switch appState.currentMode {
        case .geminiLive:
            CircleButton(icon: "mic.circle", size: 40, label: "Switch to Voice Mode") {
                appState.switchMode(to: .direct)
            }
        case .openaiRealtime:
            CircleButton(icon: "mic.circle", size: 40, label: "Switch to Voice Mode") {
                appState.switchMode(to: .direct)
            }
        case .direct:
            CircleButton(
                icon: "waveform.circle.fill",
                size: 40,
                badge: "G",
                label: "Switch to Gemini Live"
            ) {
                appState.switchMode(to: .geminiLive)
            }
        }
    }
}
