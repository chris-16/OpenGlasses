import Foundation
import UIKit

/// Stubbed out — GlassClaw uses ClaudeClaw backend, not on-device models.
@MainActor
final class LocalLLMService: ObservableObject {
    @Published var isModelLoaded = false
    @Published var downloadProgress: Double = 0
    @Published var isDownloading = false
    @Published var isGenerating = false
    @Published var loadedModelId: String?

    static let recommendedModels: [RecommendedModel] = []
    static let visionModelIds: Set<String> = []

    var isVisionModel: Bool { false }

    func downloadModel(_ modelId: String) async throws {
        throw LocalLLMError.modelNotLoaded
    }

    func loadModel(_ modelId: String) async throws {
        throw LocalLLMError.modelNotLoaded
    }

    func unloadModel() {
        loadedModelId = nil
        isModelLoaded = false
    }

    func generate(
        userMessage: String,
        systemPrompt: String,
        history: [(role: String, content: String)] = []
    ) async throws -> String {
        throw LocalLLMError.modelNotLoaded
    }

    var modelDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    func isModelDownloaded(_ modelId: String) -> Bool { false }
    func modelSizeOnDisk(_ modelId: String) -> Int64 { 0 }
    func deleteModel(_ modelId: String) throws {}
    func downloadedModelIds() -> [String] { [] }
}

// MARK: - Types

enum LocalLLMError: LocalizedError {
    case modelNotLoaded
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Local models disabled — using ClaudeClaw backend."
        case .generationFailed(let reason):
            return "Local model generation failed: \(reason)"
        }
    }
}

struct RecommendedModel: Identifiable {
    let id: String
    let name: String
    let estimatedSize: String
    let hasVision: Bool
    let hasToolCalling: Bool
    let notes: String
}
