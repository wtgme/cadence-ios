import Testing
@testable import Cadence

struct TasteMemoryTests {

    @Test func returnsEmptyStringWhenFeedbackCountBelowMinimum() {
        var memory = UserTasteMemory()
        memory.genreScores["electronic"] = 0.8
        memory.feedbackCount = 2
        let result = TasteMemoryRepositoryImpl.buildTasteContext(from: memory)
        #expect(result.isEmpty)
    }

    @Test func returnsContextStringWhenFeedbackCountMeetsMinimum() {
        var memory = UserTasteMemory()
        memory.genreScores["electronic"] = 0.8
        memory.feedbackCount = 3
        let result = TasteMemoryRepositoryImpl.buildTasteContext(from: memory)
        #expect(!result.isEmpty)
        #expect(result.contains("electronic"))
    }

    @Test func preferredGenresAppearWithPositiveSign() {
        var memory = UserTasteMemory()
        memory.genreScores = ["jazz": 0.6, "rock": 0.3]
        memory.feedbackCount = 5
        let result = TasteMemoryRepositoryImpl.buildTasteContext(from: memory)
        #expect(result.contains("Preferred genres"))
        #expect(result.contains("jazz (+0.60)"))
        #expect(result.contains("rock (+0.30)"))
    }

    @Test func avoidedGenresAppearUnderAvoidSection() {
        var memory = UserTasteMemory()
        memory.genreScores = ["jazz": -0.5]
        memory.feedbackCount = 4
        let result = TasteMemoryRepositoryImpl.buildTasteContext(from: memory)
        #expect(result.contains("Avoid genres"))
        #expect(result.contains("jazz (-0.50)"))
    }

    @Test func scoresBelowDisplayThresholdAreOmitted() {
        var memory = UserTasteMemory()
        memory.genreScores = ["folk": 0.10]   // below 0.20 threshold
        memory.feedbackCount = 5
        let result = TasteMemoryRepositoryImpl.buildTasteContext(from: memory)
        #expect(!result.contains("folk"))
    }

    @Test func nonGenreTagsAppearUnderTagsSections() {
        var memory = UserTasteMemory()
        memory.tagScores = ["energetic": 0.75, "melancholic": -0.40]
        memory.feedbackCount = 4
        let result = TasteMemoryRepositoryImpl.buildTasteContext(from: memory)
        #expect(result.contains("Preferred tags"))
        #expect(result.contains("energetic (+0.75)"))
        #expect(result.contains("Avoid tags"))
        #expect(result.contains("melancholic (-0.40)"))
    }

    @Test func honourDisclaimerAppearsInNonEmptyContext() {
        var memory = UserTasteMemory()
        memory.genreScores = ["pop": 0.5]
        memory.feedbackCount = 5
        let result = TasteMemoryRepositoryImpl.buildTasteContext(from: memory)
        #expect(result.contains("Honour these unless overridden"))
    }

    @Test func alphaConstantIsWithinExpectedLearningRange() {
        #expect(TasteMemoryRepositoryImpl.alpha >= 0.1 && TasteMemoryRepositoryImpl.alpha <= 0.5)
    }

    @Test func repeatedPositiveSignalsDriveScoreTowardOne() {
        var score: Float = 0
        for _ in 0..<20 {
            score = TasteMemoryRepositoryImpl.ema(current: score, signal: 1)
        }
        #expect(score > 0.95)
    }

    @Test func repeatedNegativeSignalsDriveScoreTowardMinusOne() {
        var score: Float = 0
        for _ in 0..<20 {
            score = TasteMemoryRepositoryImpl.ema(current: score, signal: -1)
        }
        #expect(score < -0.95)
    }
}
