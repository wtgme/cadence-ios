import SwiftUI

/// 3-step onboarding flow: Welcome → Permissions → ApiSetup → Ready → Player.
struct OnboardingFlowView: View {
    enum Step { case welcome, permissions, apiSetup, ready }

    let start: Step
    let onFinished: () -> Void
    @State private var step: Step

    init(start: Step, onFinished: @escaping () -> Void) {
        self.start = start
        self.onFinished = onFinished
        _step = State(initialValue: start)
    }

    var body: some View {
        Group {
            switch step {
            case .welcome:
                WelcomeScreen(onGetStarted: { step = .permissions })
            case .permissions:
                PermissionsScreen(onAllGranted: { step = .apiSetup })
            case .apiSetup:
                ApiSetupScreen(onSaveAndContinue: { step = .ready })
            case .ready:
                ReadyScreen(onStartListening: onFinished)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut, value: step)
    }
}
