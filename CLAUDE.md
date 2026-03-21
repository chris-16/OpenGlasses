# OpenGlasses - Development Guide

## Project Overview
OpenGlasses is an iOS app for Ray-Ban Meta smart glasses. It provides voice-controlled AI assistance with 36+ native tools, multi-LLM support (Anthropic Claude, Google Gemini, OpenAI), live camera streaming, video recording, and RTMP broadcasting.

## Architecture
- **Swift/SwiftUI** iOS app with no storyboards
- **NativeTool protocol**: `name`, `description`, `parametersSchema`, `execute(args:) async throws -> String`
- **NativeToolRegistry**: Central registry, initialized with `LocationService` and `ConversationStore`
- **NativeToolRouter**: Dispatches tool calls — native tools first, OpenClaw fallback
- **Three LLM modes**: Direct (wake word + any LLM), Gemini Live, OpenAI Realtime
- **ElevenLabs TTS** with iOS AVSpeechSynthesizer fallback

## Key Files
- `Sources/App/OpenGlassesApp.swift` — AppState, main flow, wake word → transcription → LLM → TTS
- `Sources/Utils/Config.swift` — All settings, default system prompt, wake word config
- `Sources/Services/LLMService.swift` — Multi-provider LLM service with tool calling
- `Sources/Services/NativeTools/` — All 36+ native tools
- `Sources/Services/TextToSpeechService.swift` — TTS with sanitization, thinking sound, tones
- `Sources/Services/WakeWordService.swift` — Speech recognition wake word detection
- `Sources/Services/CameraService.swift` — Glasses camera, frame publisher
- `Sources/Services/GeminiLive/` — Gemini Live session + audio
- `Sources/Services/OpenAIRealtime/` — OpenAI Realtime session + audio

## Adding a New Tool
1. Create `Sources/Services/NativeTools/YourTool.swift` implementing `NativeTool`
2. Register in `NativeToolRegistry.init()`
3. Add tool description to system prompts in both `LLMService.swift` and `GeminiLiveSessionManager.swift`
4. Add PBXBuildFile + PBXFileReference + group entry + Sources build phase entry in `project.pbxproj`
5. Add any required Info.plist privacy keys

## Build & Run
- Xcode 15+, iOS 17+ target
- Requires physical device for Bluetooth, camera, HomeKit
- SPM dependencies: HaishinKit (RTMP), MetaWearSDK

---

## Future Feature Ideas (Prioritized)

### Tier 1 — DONE
- **Ambient Captions**: `AmbientCaptionService` + `AmbientCaptionOverlay` — continuous transcription on phone screen
- **Face Recognition**: `FaceRecognitionService` + `FaceRecognitionTool` — Vision framework face embedding, local JSON DB, auto-announce via TTS
- **Memory Rewind**: `MemoryRewindService` + `MemoryRewindTool` — rolling 10-min audio buffer, on-demand transcription
- Speaker Diarization — NOT YET DONE (needs Deepgram integration)

### Tier 2 — DONE
- **Geofencing**: `GeofenceTool` — CLLocationManager region monitoring, TTS alerts on enter/exit, UserDefaults persistence
- **Proactive Suggestions**: Already covered by `ProactiveAlertService` (calendar-based). Extended with geofencing alerts.
- **Meeting Summaries**: `MeetingSummaryTool` — extracts key topics, decisions, action items from ambient caption history, saves as note
- **Perplexity Search**: Integrated into `WebSearchTool` — uses Perplexity AI when API key is configured, falls back to DuckDuckGo. Settings UI for API key.
- **Multi-Channel Messaging**: `MultiChannelMessageTool` (`send_via`) — WhatsApp, Telegram, Email via URL schemes + contact lookup
- **Privacy Filter**: `PrivacyFilterService` — Vision face detection + CIFilter Gaussian blur on bystander faces. Toggle in Settings.

### Tier 3 — DONE
- **Emotion-Aware TTS**: `TextToSpeechService.SpeechEmotion` — keyword-based sentiment detection (happy, excited, concerned, calm, empathetic), adjusts ElevenLabs stability/style and iOS speech rate/pitch. Toggle in Settings.
- **WebRTC Browser Streaming**: `WebRTCStreamingService` — WebSocket-based MJPEG streaming to web browsers. Generates shareable room URL, tracks viewer count, heartbeat keepalive. Configurable signaling server URL.
- **OpenClaw Skill Discovery**: `OpenClawSkillsTool` (`openclaw_skills`) — list, search, and get info on OpenClaw gateway skills. Checks gateway status. Falls back to asking gateway directly if skills endpoint unavailable.
- **Fitness/Health Coaching**: `FitnessCoachingTool` (`fitness_coach`) — workout session tracking (start/stop/log), HealthKit integration (read history, save workouts), MET-based calorie estimation, step goals. `PoseAnalyzer` static utility for Vision-based body pose analysis (squat/push-up/lunge form checking).
