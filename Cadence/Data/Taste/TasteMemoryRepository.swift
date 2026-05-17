import Foundation
import Combine

protocol TasteMemoryRepository: AnyObject {
    var tasteMemoryPublisher: AnyPublisher<UserTasteMemory, Never> { get }
    var currentMemory: UserTasteMemory { get }
    func recordFeedback(params: SongParams, scene: Scene?, signal: Float) async
    func buildTasteContext() -> String
    func reset() async
}

/// UserDefaults-backed implementation. EMA updates with α=0.25 → ~8 signals to steady state.
final class TasteMemoryRepositoryImpl: TasteMemoryRepository, ObservableObject {

    static let alpha: Float = 0.25
    static let displayThreshold: Float = 0.20
    static let minFeedbackForContext = 3
    static let knownGenres: Set<String> = [
        "pop", "jazz", "rock", "electronic", "ambient", "classical",
        "funk", "r&b", "hip-hop", "folk", "new-age", "blues",
    ]

    @Published private(set) var memory: UserTasteMemory
    private let store: UserDefaults
    private let key = "taste_memory_v1"

    var tasteMemoryPublisher: AnyPublisher<UserTasteMemory, Never> { $memory.eraseToAnyPublisher() }
    var currentMemory: UserTasteMemory { memory }

    init(store: UserDefaults = .standard) {
        self.store = store
        if let data = store.data(forKey: key),
           let decoded = try? JSONDecoder().decode(UserTasteMemory.self, from: data) {
            self.memory = decoded
        } else {
            self.memory = UserTasteMemory()
        }
    }

    func recordFeedback(params: SongParams, scene: Scene?, signal: Float) async {
        let clamped = max(-1, min(1, signal))
        guard let descriptions = params.descriptions else { return }
        let tags = descriptions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        if tags.isEmpty { return }
        let genres = tags.filter { Self.knownGenres.contains($0) }

        var updated = memory
        for genre in genres {
            updated.genreScores[genre] = Self.ema(current: updated.genreScores[genre] ?? 0, signal: clamped)
        }
        for tag in tags {
            updated.tagScores[tag] = Self.ema(current: updated.tagScores[tag] ?? 0, signal: clamped)
        }
        if let scene = scene {
            for genre in genres {
                let key = "\(scene.rawValue):\(genre)"
                updated.contextGenreScores[key] = Self.ema(current: updated.contextGenreScores[key] ?? 0, signal: clamped)
            }
        }
        updated.feedbackCount += 1
        updated.lastUpdatedMs = Int64(Date().timeIntervalSince1970 * 1000)

        await MainActor.run { self.memory = updated }
        persist(updated)
    }

    func buildTasteContext() -> String {
        Self.buildTasteContext(from: memory)
    }

    func reset() async {
        await MainActor.run { self.memory = UserTasteMemory() }
        store.removeObject(forKey: key)
    }

    private func persist(_ memory: UserTasteMemory) {
        if let encoded = try? JSONEncoder().encode(memory) {
            store.set(encoded, forKey: key)
        }
    }

    static func ema(current: Float, signal: Float) -> Float {
        let v = current * (1 - alpha) + signal * alpha
        return max(-1, min(1, v))
    }

    static func buildTasteContext(from memory: UserTasteMemory) -> String {
        if memory.feedbackCount < minFeedbackForContext { return "" }

        var sb = "Listener taste memory (\(memory.feedbackCount) signals learned):\n"

        let preferredGenres = memory.genreScores
            .filter { $0.value >= displayThreshold }
            .sorted { $0.value > $1.value }
            .prefix(4)
        let avoidedGenres = memory.genreScores
            .filter { $0.value <= -displayThreshold }
            .sorted { $0.value < $1.value }
            .prefix(3)

        if !preferredGenres.isEmpty {
            sb += "  Preferred genres : "
                + preferredGenres.map { "\($0.key) (\(fmtScore($0.value)))" }.joined(separator: ", ")
                + "\n"
        }
        if !avoidedGenres.isEmpty {
            sb += "  Avoid genres     : "
                + avoidedGenres.map { "\($0.key) (\(fmtScore($0.value)))" }.joined(separator: ", ")
                + "\n"
        }

        let nonGenreTags = memory.tagScores.filter { !knownGenres.contains($0.key) }
        let preferredTags = nonGenreTags
            .filter { $0.value >= displayThreshold }
            .sorted { $0.value > $1.value }
            .prefix(5)
        let avoidedTags = nonGenreTags
            .filter { $0.value <= -displayThreshold }
            .sorted { $0.value < $1.value }
            .prefix(3)

        if !preferredTags.isEmpty {
            sb += "  Preferred tags   : "
                + preferredTags.map { "\($0.key) (\(fmtScore($0.value)))" }.joined(separator: ", ")
                + "\n"
        }
        if !avoidedTags.isEmpty {
            sb += "  Avoid tags       : "
                + avoidedTags.map { "\($0.key) (\(fmtScore($0.value)))" }.joined(separator: ", ")
                + "\n"
        }

        let contextEntries = memory.contextGenreScores
            .filter { abs($0.value) >= displayThreshold }
            .sorted { $0.value > $1.value }
            .prefix(4)
        if !contextEntries.isEmpty {
            sb += "  Scene context    : "
                + contextEntries.map { "\($0.key) (\(fmtScore($0.value)))" }.joined(separator: ", ")
                + "\n"
        }

        sb += "  Honour these unless overridden by stress ≥ 7 or SpO2 rules."
        return sb.trimmingCharacters(in: .whitespaces)
    }

    private static func fmtScore(_ v: Float) -> String {
        v >= 0 ? "+\(String(format: "%.2f", v))" : "\(String(format: "%.2f", v))"
    }
}
