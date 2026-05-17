import Foundation
import Combine

protocol GenerationRepository: AnyObject {
    /// Params emitted as soon as Step 1 completes, before Step 2 (audio rendering).
    var translatedSongParamsPublisher: AnyPublisher<SongParams?, Never> { get }
    var translatedSongParamsValue: SongParams? { get }

    /// Mental state estimated by Step 1a, populated before `translatedSongParams`.
    var translatedMentalStatePublisher: AnyPublisher<MentalState?, Never> { get }
    var translatedMentalStateValue: MentalState? { get }

    /// Step 1 (full) — Biometric context → MentalState → SongParams. Always returns usable params.
    func translateMetrics(metricsContext: String) async throws -> SongParams

    /// Step 1b only — derives SongParams from an already-estimated MentalState.
    /// Returns nil if Step 1b fails — caller should fall back to translateMetrics.
    func translateMentalState(_ mentalState: MentalState, previousParams: SongParams?) async -> SongParams?

    /// Step 2 — Audio generation via the active backend. Yields chunks via AsyncStream.
    func generateAudioStream(params: SongParams) -> AsyncStream<StreamingChunk>
}

protocol GenerationBackend: AnyObject {
    var name: String { get }
    func generate(params: SongParams) async -> GenerationResult
    func generateStream(params: SongParams) -> AsyncStream<StreamingChunk>
    func healthCheck() async -> Bool
}
