import Foundation
import AVFoundation
import Combine
import UIKit

/// Records video from a stream of UIImage frames to an .mp4 file.
@MainActor
class VideoRecordingService: ObservableObject {
    @Published var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var durationTimer: Timer?
    private var recordingStartDate: Date?
    private var outputURL: URL?
    private var frameSubscription: AnyCancellable?

    // These are accessed from the background recording queue
    private nonisolated(unsafe) var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private nonisolated(unsafe) var startTime: CMTime?
    private nonisolated(unsafe) var frameCount: Int64 = 0

    var formattedDuration: String {
        let mins = Int(recordingDuration) / 60
        let secs = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    /// Start recording frames from the given publisher.
    func startRecording(from publisher: PassthroughSubject<UIImage, Never>, bitrate: Int = 1_500_000) throws {
        guard !isRecording else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "GlassClaw_\(Int(Date().timeIntervalSince1970)).mp4"
        let url = tempDir.appendingPathComponent(fileName)

        // Clean up any previous file at this path
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        // Video input — dimensions set from first frame
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 640,
            AVVideoHeightKey: 480,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoInput.expectsMediaDataInRealTime = true

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 640,
            kCVPixelBufferHeightKey as String: 480
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: attrs
        )

        writer.add(videoInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        self.writer = writer
        self.videoInput = videoInput
        self.adaptor = adaptor
        self.outputURL = url
        self.startTime = nil
        self.frameCount = 0
        self.recordingDuration = 0
        self.recordingStartDate = Date()
        self.isRecording = true

        // Subscribe to frames on a background queue
        frameSubscription = publisher
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .sink { [weak self] image in
                self?.appendFrame(image)
            }

        // Duration timer
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStartDate else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }

        NSLog("[Recording] Started → %@", url.lastPathComponent)
    }

    /// Stop recording and return the URL of the finished .mp4.
    func stopRecording() async -> URL? {
        guard isRecording else { return nil }

        frameSubscription?.cancel()
        frameSubscription = nil
        durationTimer?.invalidate()
        durationTimer = nil
        isRecording = false

        guard let writer, let videoInput else { return nil }

        videoInput.markAsFinished()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                cont.resume()
            }
        }

        let url = outputURL
        NSLog("[Recording] Finished → %@ (%.1fs, %lld frames)",
              url?.lastPathComponent ?? "nil", recordingDuration, frameCount)

        self.writer = nil
        self.videoInput = nil
        self.adaptor = nil
        self.outputURL = nil
        self.startTime = nil

        return url
    }

    // MARK: - Private

    private nonisolated func appendFrame(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return }

        let width = cgImage.width
        let height = cgImage.height

        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Calculate presentation time
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        let presentationTime: CMTime
        if let start = startTime {
            presentationTime = CMTimeSubtract(now, start)
        } else {
            startTime = now
            presentationTime = .zero
        }

        guard let adaptor, adaptor.assetWriterInput.isReadyForMoreMediaData else { return }
        adaptor.append(buffer, withPresentationTime: presentationTime)
        frameCount += 1
    }
}
