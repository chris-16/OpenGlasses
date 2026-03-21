import Foundation
import Speech
import AVFoundation

/// Rolling audio buffer that stores the last N minutes of ambient audio.
/// On demand, transcribes the buffer and provides an AI-summarized recap.
/// "What did they just say?" → transcribes recent audio → summarizes.
@MainActor
class MemoryRewindService: ObservableObject {
    @Published var isActive = false
    @Published var bufferDurationMinutes: Double = 0

    /// How many minutes of audio to keep (configurable)
    var maxBufferMinutes: Double = 10.0

    /// Audio buffer — stores raw PCM samples
    private var audioBuffer: Data = Data()
    private var bufferSampleRate: Double = 16000
    private var bufferStartTime: Date?

    /// Bytes per minute at 16kHz mono 16-bit = 16000 * 2 * 60 = 1,920,000
    private var bytesPerMinute: Int { Int(bufferSampleRate) * 2 * 60 }
    private var maxBufferBytes: Int { Int(maxBufferMinutes) * bytesPerMinute }

    /// Reference to wake word service for audio tap
    weak var wakeWordService: WakeWordService?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    // MARK: - Public API

    func start() {
        guard !isActive else { return }
        isActive = true
        audioBuffer = Data()
        bufferStartTime = Date()

        // Hook into the audio buffer stream (named consumer)
        wakeWordService?.addAudioBufferConsumer(id: "memory_rewind") { [weak self] buffer in
            Task { @MainActor in
                self?.appendAudioBuffer(buffer)
            }
        }

        print("⏪ Memory rewind started (keeping \(Int(maxBufferMinutes)) min)")
    }

    func stop() {
        isActive = false
        wakeWordService?.removeAudioBufferConsumer(id: "memory_rewind")
        audioBuffer = Data()
        bufferStartTime = nil
        bufferDurationMinutes = 0
        print("⏪ Memory rewind stopped")
    }

    /// Transcribe the last N minutes (or all buffered audio) and return text
    func rewind(lastMinutes: Double = 2.0) async -> String {
        guard isActive else {
            return "Memory rewind is not active. Enable it in settings first."
        }

        guard !audioBuffer.isEmpty else {
            return "No audio buffered yet. Keep it running for a bit."
        }

        let minutesToTranscribe = min(lastMinutes, bufferDurationMinutes)
        let bytesToUse = min(Int(minutesToTranscribe) * bytesPerMinute, audioBuffer.count)

        guard bytesToUse > 0 else {
            return "Not enough audio buffered."
        }

        // Take the most recent N bytes
        let recentAudio = audioBuffer.suffix(bytesToUse)

        print("⏪ Rewinding \(String(format: "%.1f", minutesToTranscribe)) min (\(recentAudio.count) bytes)...")

        // Convert raw PCM data to a WAV file for speech recognition
        let wavData = createWAV(from: recentAudio, sampleRate: bufferSampleRate)

        do {
            let transcript = try await transcribeAudio(wavData)
            if transcript.isEmpty {
                return "I couldn't make out any speech in the last \(Int(minutesToTranscribe)) minutes of audio."
            }
            return "Here's what was said in the last \(Int(minutesToTranscribe)) minutes:\n\n\(transcript)\n\nThe LLM should now summarize this for the user in a natural, conversational way."
        } catch {
            return "Transcription failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Audio Buffer Management

    private func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Convert to 16-bit PCM data
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate
        bufferSampleRate = sampleRate

        // Convert float samples to Int16
        var pcmData = Data(capacity: frameCount * 2)
        for i in 0..<frameCount {
            let sample = channelData[0][i]
            let clamped = max(-1.0, min(1.0, sample))
            var int16Sample = Int16(clamped * Float(Int16.max))
            pcmData.append(Data(bytes: &int16Sample, count: 2))
        }

        audioBuffer.append(pcmData)

        // Trim to max size
        if audioBuffer.count > maxBufferBytes {
            let excess = audioBuffer.count - maxBufferBytes
            audioBuffer.removeFirst(excess)
        }

        // Update duration
        Task { @MainActor in
            bufferDurationMinutes = Double(audioBuffer.count) / Double(bytesPerMinute)
        }
    }

    // MARK: - Transcription

    private func transcribeAudio(_ wavData: Data) async throws -> String {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw RewindError.recognizerUnavailable
        }

        // Write to temp file (SFSpeechURLRecognitionRequest needs a file URL)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("rewind_\(UUID().uuidString).wav")
        try wavData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let request = SFSpeechURLRecognitionRequest(url: tempURL)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                if let result = result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    // MARK: - WAV Creation

    private func createWAV(from pcmData: Data, sampleRate: Double) -> Data {
        var data = Data()
        let dataSize = UInt32(pcmData.count)
        let fileSize = UInt32(36 + dataSize)

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // mono
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })   // block align
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })  // bits/sample

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        data.append(pcmData)

        return data
    }
}

enum RewindError: LocalizedError {
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "Speech recognizer not available"
        }
    }
}
