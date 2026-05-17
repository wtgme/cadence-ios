import SwiftUI

@main
struct CadenceApp: App {
    init() {
        DIContainer.shared.bootstrap()
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}
