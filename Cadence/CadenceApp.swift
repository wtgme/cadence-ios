import SwiftUI
import AVFoundation

@main
struct CadenceApp: App {
    init() {
        // Register the .playback category at launch so iOS knows this app plays background
        // audio before the user ever presses play. setActive(true) is deferred to
        // MusicPlayer.startPlayback() so the audio indicator only appears when playing.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        DIContainer.shared.bootstrap()
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}
