import SwiftUI

struct RootView: View {
    @StateObject private var nav = OnboardingNavViewModel()

    var body: some View {
        Group {
            switch nav.startDestination {
            case .none:
                ZStack { CadenceColor.bg.ignoresSafeArea() }
            case .welcome:
                OnboardingFlowView(start: .welcome, onFinished: nav.markComplete)
            case .apiSetupFirstRun:
                ApiSetupScreen(isFirstRun: true) { nav.markApiSetupSeen() }
            case .player:
                PlayerScreen()
            }
        }
        .animation(.easeInOut, value: nav.startDestination)
    }
}
