import Foundation
import AVFoundation
import MediaPlayer
import Combine
import OSLog

/// AVPlayer-backed equivalent of `MusicPlayerService`. Configures `AVAudioSession`
/// for background music playback and exposes remote-command control via the lock-screen.
final class MusicPlayer {

    private static let log = Logger(subsystem: "io.cadence.music", category: "MusicPlayer")
    private static let maxHistory = 5

    private let bufferManager: AudioBufferManager
    private let player = AVQueuePlayer()
    private var queueObserver: NSKeyValueObservation?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var positionTimer: Timer?

    /// Files queued into AVPlayer in order. Head is the currently-playing item.
    private var enqueuedFiles: [URL] = []
    /// Files that have finished playing — kept on disk for "previous" navigation.
    private var playedFiles: [URL] = []

    private var feedTask: Task<Void, Never>?
    private var isPlaying = false

    init(bufferManager: AudioBufferManager) {
        self.bufferManager = bufferManager
    }

    func startPlayback() {
        configureAudioSession()
        registerRemoteCommands()
        isPlaying = true
        feedTask?.cancel()
        feedTask = Task { [weak self] in
            guard let self else { return }
            guard let first = await self.bufferManager.takeNext() else {
                Self.log.warning("Buffer returned nil — no audio to play")
                return
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

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.player.play(); return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.player.pause(); return .success
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
        Task { [weak self] in
            guard let self else { return }
            guard let next = await self.bufferManager.takeNext() else { return }
            await MainActor.run { self.enqueueFile(next) }
        }
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

// Helper to clear now-playing without importing UIKit at the top level.
private func UIApplicationClearNowPlayingInfo() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
}
