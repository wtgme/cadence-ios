import Foundation

final class OnboardingRepository {
    private let store: UserDefaults
    private enum Key {
        static let completed = "onboarding_completed"
        static let apiSetupSeen = "onboarding_api_setup_seen"
    }

    init(store: UserDefaults = .standard) { self.store = store }

    var completed: Bool {
        get { store.bool(forKey: Key.completed) }
    }

    var apiSetupSeen: Bool {
        get { store.bool(forKey: Key.apiSetupSeen) }
    }

    func markCompleted() { store.set(true, forKey: Key.completed) }
    func markApiSetupSeen() { store.set(true, forKey: Key.apiSetupSeen) }
}
