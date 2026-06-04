import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import Combine
import OSLog

/// AVPlayer-backed equivalent of `MusicPlayerService`. Configures `AVAudioSession`
/// for background music playback and exposes remote-command control via the lock-screen.
final class MusicPlayer {

    private static let log = Logger(subsystem: "io.cadence.music", category: "MusicPlayer")
    private static let maxHistory = 5
    private static let welcomePadVolume: Float = 0.30
    private static let welcomeFadeMs: Int = 600

    private let bufferManager: AudioBufferManager
    private let player = AVQueuePlayer()
    private var queueObserver: NSKeyValueObservation?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var positionTimer: Timer?

    /// Files queued into AVPlayer in order. Head is the currently-playing item.
    private var enqueuedFiles: [URL] = []
    /// Files that have finished playing — kept on disk for "previous" navigation.
    private var playedFiles: [URL] = []

    private var feedTask: Task<Void, Never>?
    private var routeChangeObserver: NSObjectProtocol?
    private var isPlaying = false

    /// Looping low-volume pad played while the first real song is generating.
    /// Mirrors Android's MusicPlayerService.maybeStartWelcomePad().
    private var padPlayer: AVQueuePlayer?
    private var padLooper: AVPlayerLooper?

    init(bufferManager: AudioBufferManager) {
        self.bufferManager = bufferManager
    }

    func startPlayback() {
        configureAudioSession()
        registerRemoteCommands()
        setupAudioSessionObservers()
        isPlaying = true
        feedTask?.cancel()

        if let old = endObserver {
            NotificationCenter.default.removeObserver(old)
            endObserver = nil
        }

        // Skip the welcome pad when pre-buffered audio is already available — go straight to music.
        let padStarted = !bufferManager.hasBufferedAudio && startWelcomePad()

        feedTask = Task { [weak self] in
            guard let self else { return }
            guard let first = await self.bufferManager.takeNext() else {
                Self.log.warning("Buffer returned nil — no audio to play")
                if padStarted { await self.fadeOutWelcomePad() }
                return
            }
            if padStarted {
                await self.fadeOutWelcomePad()
            }
            await MainActor.run { self.enqueueFile(first) }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            self?.handleItemEnded()
        }
        startPositionUpdates()
    }

    func stop() {
        isPlaying = false
        feedTask?.cancel()
        feedTask = nil
        positionTimer?.invalidate()
        positionTimer = nil
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
        padPlayer?.pause()
        padPlayer?.removeAllItems()
        padPlayer = nil
        padLooper = nil
        player.pause()
        player.removeAllItems()
        for url in enqueuedFiles { try? FileManager.default.removeItem(at: url) }
        for url in playedFiles { try? FileManager.default.removeItem(at: url) }
        enqueuedFiles.removeAll()
        playedFiles.removeAll()
        bufferManager.updateHasPrevious(false)
        bufferManager.updateProgress(positionMs: 0, durationMs: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        UIApplicationClearNowPlayingInfo()
    }

    func skipToNext() {
        if player.items().count > 1 {
            // Next item already pre-loaded — advance instantly.
            player.advanceToNextItem()
        } else {
            // Next song still generating. Move current to history; let feed loop deliver it.
            if let current = enqueuedFiles.first {
                playedFiles.append(current)
                enqueuedFiles.removeFirst()
                bufferManager.updateHasPrevious(true)
            }
            for url in enqueuedFiles.dropFirst() {
                try? FileManager.default.removeItem(at: url)
            }
            enqueuedFiles = enqueuedFiles.isEmpty ? [] : [enqueuedFiles[0]]
            player.removeAllItems()
            bufferManager.notifySkipToNext()
        }
    }

    func skipToPrevious() {
        guard let previousFile = playedFiles.last else {
            // No history — restart current song.
            player.seek(to: .zero)
            if isPlaying { player.play() }
            return
        }
        playedFiles.removeLast()
        bufferManager.updateHasPrevious(!playedFiles.isEmpty)

        let currentFiles = enqueuedFiles
        enqueuedFiles.removeAll()
        player.removeAllItems()

        // previous song + the rest of currently-queued files
        let all = [previousFile] + currentFiles
        for f in all {
            let item = AVPlayerItem(url: f)
            player.insert(item, after: nil)
            enqueuedFiles.append(f)
        }
        if isPlaying { player.play() }
    }

    func seek(positionMs: Int64) {
        let t = CMTime(seconds: Double(positionMs) / 1000, preferredTimescale: 1000)
        player.seek(to: t)
    }

    // MARK: - Private

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            Self.log.error("AudioSession config failed: \(error.localizedDescription)")
        }
    }

    private func setupAudioSessionObservers() {
        if let old = interruptionObserver {
            NotificationCenter.default.removeObserver(old)
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioSessionInterruption(notification)
        }

        if let old = routeChangeObserver {
            NotificationCenter.default.removeObserver(old)
        }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioRouteChange(notification)
        }
    }

    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            break // system pauses AVQueuePlayer automatically
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            guard options.contains(.shouldResume) else { return }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                if isPlaying { player.play() }
            } catch {
                Self.log.error("Audio session reactivation failed after interruption: \(error.localizedDescription)")
            }
        @unknown default:
            break
        }
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        if reason == .oldDeviceUnavailable {
            // Headphones or BT device removed — system already paused AVPlayer.
            // Mark intent as paused so the queue feed doesn't auto-restart,
            // matching iOS standard behavior (user must tap play to resume on speaker).
            isPlaying = false
            updateNowPlaying()
        }
    }

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        // Remove stale targets that pile up when startPlayback() is called more than once.
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.isPlaying = true
            self.player.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.isPlaying = false
            self.player.pause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.skipToNext(); return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.skipToPrevious(); return .success
        }
    }

    private func enqueueFile(_ url: URL) {
        let item = AVPlayerItem(url: url)
        let wasIdle = player.items().isEmpty || player.timeControlStatus == .paused
        player.insert(item, after: player.items().last)
        enqueuedFiles.append(url)
        Self.log.debug("Queued: \(url.lastPathComponent)")
        if wasIdle && isPlaying {
            player.play()
            feedNextChunk()
        }
        updateNowPlaying()
    }

    private func handleItemEnded() {
        if let played = enqueuedFiles.first {
            enqueuedFiles.removeFirst()
            playedFiles.append(played)
            while playedFiles.count > Self.maxHistory {
                let dropped = playedFiles.removeFirst()
                try? FileManager.default.removeItem(at: dropped)
            }
            bufferManager.updateHasPrevious(true)
        }
        feedNextChunk()
    }

    private func feedNextChunk() {
        // Request background execution time so iOS doesn't suspend the app during
        // the brief window between the current song ending and the next one being
        // enqueued. Without this, a slow generation response (~30-90s) on the
        // transition can cause the process to freeze mid-fetch.
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "MusicTransition") {
            // Expiry: iOS is about to suspend — end the token so the system doesn't
            // terminate the app with a watchdog exception.
            UIApplication.shared.endBackgroundTask(bgTask)
        }
        Task { [weak self] in
            defer { UIApplication.shared.endBackgroundTask(bgTask) }
            guard let self else { return }
            guard let next = await self.bufferManager.takeNext() else { return }
            await MainActor.run { self.enqueueFile(next) }
        }
    }

    /// Plays `welcome_pad.mp3` from the bundle on loop at low volume while the
    /// first real song is generating. Returns true if the pad was started.
    /// Mirrors Android's MusicPlayerService.maybeStartWelcomePad().
    private func startWelcomePad() -> Bool {
        guard padPlayer == nil else { return false }
        guard let url = Bundle.main.url(forResource: "welcome_pad", withExtension: "mp3") else {
            Self.log.debug("No welcome_pad asset — starting silently")
            return false
        }
        let item = AVPlayerItem(url: url)
        let p = AVQueuePlayer()
        let looper = AVPlayerLooper(player: p, templateItem: item)
        p.volume = Self.welcomePadVolume
        p.play()
        self.padPlayer = p
        self.padLooper = looper
        Self.log.debug("Welcome pad playing (volume=\(Self.welcomePadVolume))")
        return true
    }

    /// Fades the welcome pad to zero over `welcomeFadeMs`, then stops it.
    /// Called once the first real chunk has been pulled from the buffer, immediately
    /// before it is enqueued into the main player.
    private func fadeOutWelcomePad() async {
        guard let p = padPlayer else { return }
        let steps = 10
        let stepNs = UInt64(Self.welcomeFadeMs * 1_000_000 / steps)
        let startVol = p.volume
        for i in 1...steps {
            try? await Task.sleep(nanoseconds: stepNs)
            p.volume = startVol * Float(1.0 - Double(i) / Double(steps))
        }
        p.pause()
        p.removeAllItems()
        padPlayer = nil
        padLooper = nil
    }

    private func startPositionUpdates() {
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = self.player.currentTime()
            let duration = self.player.currentItem?.duration ?? .zero
            let posMs = Int64(max(0, CMTimeGetSeconds(current)) * 1000)
            let durMs = CMTimeGetSeconds(duration).isFinite ? Int64(CMTimeGetSeconds(duration) * 1000) : 0
            self.bufferManager.updateProgress(positionMs: posMs, durationMs: durMs)
            self.updateNowPlaying(position: posMs, duration: durMs)
        }
    }

    private func updateNowPlaying(position: Int64? = nil, duration: Int64? = nil) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = "Cadence"
        info[MPMediaItemPropertyArtist] = "Generated track"
        if let p = position { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(p) / 1000 }
        if let d = duration, d > 0 { info[MPMediaItemPropertyPlaybackDuration] = Double(d) / 1000 }
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

private func UIApplicationClearNowPlayingInfo() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
}
