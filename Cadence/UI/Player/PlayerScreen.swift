import SwiftUI

struct PlayerScreen: View {
    @StateObject private var viewModel = PlayerViewModel()
    @State private var showSceneOverride = false
    @State private var showReasoning = false
    @State private var showSettings = false
    @State private var adjustmentExpanded = false
    @State private var showBottomSheet = false

    private var isBuffering: Bool { viewModel.playbackState == .buffering }
    private var isPlaying:   Bool { viewModel.playbackState == .playing }
    private var isActive:    Bool { viewModel.playbackState != .idle }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Scene-tinted background
            LinearGradient(
                stops: [
                    .init(color: CadenceColor.sceneTint(for: viewModel.currentScene).opacity(0.85), location: 0),
                    .init(color: CadenceColor.surface0, location: 0.5),
                    .init(color: CadenceColor.surface0, location: 1),
                ],
                startPoint: .top, endPoint: .bottom,
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.2), value: viewModel.currentScene)

            VStack(spacing: 0) {
                header
                Spacer()
                heroSection
                Spacer().frame(height: 12)
                if let params = viewModel.currentSongParams, let desc = params.descriptions, !desc.isEmpty {
                    StyleTagRow(descriptions: desc, glowColor: CadenceColor.sceneGlow(for: viewModel.currentScene))
                    Spacer().frame(height: 12)
                }
                SongTimeline(progress: viewModel.playbackProgress, isEnabled: isPlaying) { viewModel.seek(positionMs: $0) }
                    .padding(.horizontal, 4)
                if !viewModel.currentAdjustment.isEmpty {
                    AdjustmentHints(adjustment: viewModel.currentAdjustment, glow: CadenceColor.sceneGlow(for: viewModel.currentScene))
                        .padding(.top, 6)
                }
                Spacer().frame(height: 12)
                controls
                Spacer().frame(height: 16)
                if isActive {
                    TrackFeedbackRow(tasteMemory: viewModel.tasteMemory,
                                     onThumbsUp: { viewModel.thumbsUp() },
                                     onThumbsDown: { viewModel.thumbsDown() })
                }
                Spacer()
                if isActive {
                    AdjustmentPanel(
                        adjustment: viewModel.currentAdjustment,
                        expanded: $adjustmentExpanded,
                        onToggleGenre: viewModel.toggleGenre,
                        onClearGenres: viewModel.clearGenres,
                        onEnergyBias: viewModel.setEnergyBias,
                        onFreeText: viewModel.submitFreeText,
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }
                Button(action: { showBottomSheet = true }) {
                    HStack {
                        Text(viewModel.currentScene?.displayName ?? "Detecting")
                            .font(CadenceFont.labelMedium)
                            .foregroundStyle(CadenceColor.sceneGlow(for: viewModel.currentScene))
                        if viewModel.sensorState.heartRate > 0 {
                            Text("♥ \(viewModel.sensorState.heartRate)")
                                .font(CadenceFont.labelSmall)
                                .foregroundStyle(CadenceColor.sceneGlow(for: viewModel.currentScene).opacity(0.65))
                        }
                        Spacer()
                        Image(systemName: "chevron.up").foregroundStyle(CadenceColor.textTertiary)
                    }
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(CadenceColor.surface1)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)

            // Error banner
            if let err = viewModel.lastError, isActive {
                VStack {
                    ErrorBanner(message: err) { viewModel.retryGeneration() }
                        .padding(.horizontal, 16)
                        .padding(.top, 60)
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showBottomSheet) {
            NavigationStack {
                PlayerSheetContent(viewModel: viewModel)
                    .background(CadenceColor.surface1.ignoresSafeArea())
                    .navigationTitle("Details")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") { showBottomSheet = false }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showReasoning) {
            NavigationStack {
                ScrollView {
                    AIReasoningPanel(
                        metricsContext: viewModel.currentMetricsContext,
                        mentalState: viewModel.currentMentalState,
                        songParams: viewModel.currentSongParams,
                    )
                    .padding(24)
                }
                .background(CadenceColor.surface1.ignoresSafeArea())
                .navigationTitle("Why this music?")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { showReasoning = false }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showSettings) {
            SettingsScreen { showSettings = false }
                .preferredColorScheme(.dark)
        }
    }

    private var header: some View {
        HStack {
            Button(action: { showSceneOverride.toggle() }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CadenceColor.textSecondary)
                    .frame(width: 36, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSceneOverride) {
                ActivityPickerMenu(
                    currentScene: viewModel.currentScene,
                    onSelect: { scene in viewModel.overrideScene(scene); showSceneOverride = false },
                    onAutoDetect: { viewModel.clearSceneOverride(); showSceneOverride = false },
                )
                .preferredColorScheme(.dark)
                .padding(.horizontal)
            }
            Spacer()
            Text("CADENCE").font(CadenceFont.labelLarge).foregroundStyle(CadenceColor.orange)
            Spacer()
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CadenceColor.textSecondary)
                    .frame(width: 36, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private var heroSection: some View {
        VStack(spacing: 6) {
            Text(viewModel.currentScene?.displayName ?? "Detecting…")
                .font(CadenceFont.displayMedium)
                .foregroundStyle(CadenceColor.textPrimary)
                .onTapGesture { if isActive { showReasoning = true } }
            if let candidate = viewModel.candidateScene, candidate != viewModel.currentScene {
                Text("Switching to \(candidate.displayName)…")
                    .font(CadenceFont.labelMedium)
                    .foregroundStyle(CadenceColor.sceneGlow(for: viewModel.currentScene).opacity(0.7))
            }
            if viewModel.sensorState.heartRate > 0 {
                HrBadge(bpm: viewModel.sensorState.heartRate)
            }
            Spacer().frame(height: 16)
            if viewModel.isAdaptingToHrDrift {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(CadenceColor.sceneGlow(for: viewModel.currentScene))
                    Text("Heart rate shift detected — adapting music…")
                        .font(CadenceFont.labelSmall)
                        .foregroundStyle(CadenceColor.textSecondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
            }
            ZStack {
                if isBuffering {
                    GenerationProgressArc(
                        generationStartMs: viewModel.generationStartMs,
                        glowColor: CadenceColor.sceneGlow(for: viewModel.currentScene),
                    )
                } else {
                    CircularWaveformVisualizer(
                        isPlaying: isPlaying,
                        bpm: viewModel.sensorState.heartRate,
                        glowColor: CadenceColor.sceneGlow(for: viewModel.currentScene),
                    )
                }
                VStack(spacing: 6) {
                    Text(viewModel.sensorState.heartRate > 0 ? "NOW · \(viewModel.sensorState.heartRate) BPM" : "NO HR DATA")
                        .font(CadenceFont.labelMedium)
                        .foregroundStyle(CadenceColor.textSecondary)
                    WaveformVisualizer(
                        isPlaying: isPlaying,
                        bpm: viewModel.sensorState.heartRate,
                        color: isPlaying ? CadenceColor.orange : Color.white.opacity(0.3),
                    )
                    .frame(width: 120, height: 36)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button(action: { viewModel.skipToPrevious() }) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(isPlaying && viewModel.hasPrevious ? CadenceColor.textPrimary : CadenceColor.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!(isPlaying && viewModel.hasPrevious))

            Button(action: { isActive ? viewModel.stop() : viewModel.startPlayback() }) {
                Image(systemName: isActive ? "stop.fill" : "play.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color(hex: 0x0B1220))
                    .frame(width: 72, height: 72)
                    .background(
                        Circle().fill(LinearGradient(
                            colors: isBuffering
                                ? [CadenceColor.surface2, CadenceColor.surface2]
                                : (isActive
                                   ? [CadenceColor.orange, CadenceColor.orangeDeep]
                                   : [CadenceColor.blue, CadenceColor.blueDeep]),
                            startPoint: .top, endPoint: .bottom,
                        ))
                    )
            }
            .buttonStyle(.plain)

            Button(action: { viewModel.skipToNext() }) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(isPlaying ? CadenceColor.textPrimary : CadenceColor.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!isPlaying)
        }
    }
}

struct HrBadge: View {
    let bpm: Int
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(CadenceColor.red).frame(width: 11, height: 11)
            Text("\(bpm) BPM").font(CadenceFont.labelMedium).foregroundStyle(CadenceColor.orange)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(Capsule().fill(CadenceColor.orangeDim))
        .overlay(Capsule().stroke(CadenceColor.orangeDimHi, lineWidth: 1))
    }
}

struct StyleTagRow: View {
    let descriptions: String
    let glowColor: Color

    var body: some View {
        let tags = descriptions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(tags.prefix(5).enumerated()), id: \.offset) { i, tag in
                    let solid = i == 0
                    Text(tag)
                        .font(CadenceFont.titleSmall)
                        .foregroundStyle(solid ? Color(hex: 0x0B1220) : CadenceColor.orange)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(
                            Capsule().fill(solid ? CadenceColor.orange : CadenceColor.orangeDim)
                                .overlay(Capsule().stroke(CadenceColor.orangeDimHi, lineWidth: 1))
                        )
                }
            }
        }
    }
}

struct SongTimeline: View {
    let progress: PlaybackProgress
    let isEnabled: Bool
    let onSeek: (Int64) -> Void

    @State private var dragging = false
    @State private var dragFraction: Double = 0

    var body: some View {
        let fraction: Double = {
            if progress.durationMs <= 0 { return 0 }
            if dragging { return dragFraction }
            return min(1, max(0, Double(progress.positionMs) / Double(progress.durationMs)))
        }()
        let displayPosMs = dragging ? Int64(dragFraction * Double(progress.durationMs)) : progress.positionMs

        VStack(spacing: 0) {
            Slider(value: Binding(get: { fraction }, set: { v in dragging = true; dragFraction = v }),
                   in: 0...1) { editing in
                if !editing {
                    dragging = false
                    onSeek(Int64(dragFraction * Double(progress.durationMs)))
                }
            }
            .tint(CadenceColor.orange)
            .disabled(!isEnabled || progress.durationMs <= 0)
            HStack {
                Text(formatDuration(displayPosMs)).font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.textTertiary)
                Spacer()
                Text(formatDuration(progress.durationMs)).font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.textTertiary)
            }
            .padding(.horizontal, 4)
        }
    }

    private func formatDuration(_ ms: Int64) -> String {
        if ms <= 0 { return "0:00" }
        let total = ms / 1000
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

struct AdjustmentHints: View {
    let adjustment: UserMusicAdjustment
    let glow: Color
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(buildAdjustmentHints(adjustment), id: \.self) { hint in
                    Text(hint)
                        .font(CadenceFont.labelSmall)
                        .foregroundStyle(glow.opacity(0.85))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 12).fill(glow.opacity(0.15)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(glow.opacity(0.3), lineWidth: 1))
                }
            }
        }
    }
}

struct TrackFeedbackRow: View {
    let tasteMemory: UserTasteMemory
    let onThumbsUp: () -> Void
    let onThumbsDown: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Button(action: onThumbsDown) {
                    Image(systemName: "hand.thumbsdown.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(CadenceColor.feedbackNeutral)
                }
                .buttonStyle(.plain)
                VStack(spacing: 2) {
                    Text("RATE THIS TRACK").font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.textTertiary)
                    if tasteMemory.feedbackCount > 0 {
                        Text("\(tasteMemory.feedbackCount) signal\(tasteMemory.feedbackCount == 1 ? "" : "s") learned")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(CadenceColor.blue.opacity(0.5))
                    }
                }
                Button(action: onThumbsUp) {
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(CadenceColor.feedbackNeutral)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let onRetry: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.black)
            Text(message).font(CadenceFont.bodySmall).foregroundStyle(.black)
            Spacer()
            Button("Retry", action: onRetry).font(CadenceFont.labelSmall).foregroundStyle(.black).bold()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(CadenceColor.warningAmber.opacity(0.95)))
    }
}
