import Foundation
import Combine

enum OnboardingStart: Equatable {
    case welcome
    case apiSetupFirstRun
    case player
}

final class OnboardingNavViewModel: ObservableObject {

    @Published private(set) var startDestination: OnboardingStart? = nil

    private let repo: OnboardingRepository

    init(repo: OnboardingRepository = DIContainer.shared.onboardingRepository) {
        self.repo = repo
        resolve()
    }

    func markComplete() {
        repo.markCompleted()
        repo.markApiSetupSeen()
        startDestination = .player
    }

    func markApiSetupSeen() {
        repo.markApiSetupSeen()
        startDestination = .player
    }

    private func resolve() {
        if !repo.completed {
            startDestination = .welcome
        } else if !repo.apiSetupSeen {
            startDestination = .apiSetupFirstRun
        } else {
            startDestination = .player
        }
    }
}
