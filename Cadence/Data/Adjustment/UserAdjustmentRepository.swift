import Foundation
import Combine

final class UserAdjustmentRepository: ObservableObject {
    @Published private(set) var adjustment = UserMusicAdjustment()

    func toggleGenre(_ genre: String) {
        var current = adjustment.genreOverrides
        if let idx = current.firstIndex(of: genre) {
            current.remove(at: idx)
        } else {
            current.append(genre)
        }
        adjustment.genreOverrides = current
    }

    func clearGenres() { adjustment.genreOverrides = [] }

    func setEnergyBias(_ delta: Int) {
        adjustment.energyBias = max(-2, min(2, delta))
    }

    func setFreeText(_ text: String?) {
        if let t = text, !t.trimmingCharacters(in: .whitespaces).isEmpty {
            adjustment.freeText = t
        } else {
            adjustment.freeText = nil
        }
    }

    func reset() { adjustment = UserMusicAdjustment() }
}
