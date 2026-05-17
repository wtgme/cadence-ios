import Foundation

protocol ParamsBuilder {
    func buildParams(state: SensorState, scene: Scene?) async throws -> SongParams
}

/// Builds `SongParams` by calling Signal2Style once per session.
final class LLMParamsBuilder: ParamsBuilder {
    private let musicRepository: GenerationRepository
    private let promptBuilder: PromptBuilder

    init(musicRepository: GenerationRepository, promptBuilder: PromptBuilder) {
        self.musicRepository = musicRepository
        self.promptBuilder = promptBuilder
    }

    func buildParams(state: SensorState, scene: Scene?) async throws -> SongParams {
        let metricsContext = promptBuilder.buildMetricsContext(state: state, scene: scene)
        return try await musicRepository.translateMetrics(metricsContext: metricsContext)
    }
}
