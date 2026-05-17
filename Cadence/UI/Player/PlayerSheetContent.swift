import SwiftUI

/// Content of the player's pull-up bottom sheet — vitals, AI reasoning, history, taste profile.
struct PlayerSheetContent: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let diag = viewModel.healthDiagnostic {
                    Text(diag).font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.textTertiary)
                }

                Text("VITALS").font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.textTertiary)

                HStack(spacing: 10) {
                    StatCard(label: "HEART RATE", value: viewModel.sensorState.heartRate > 0 ? "\(viewModel.sensorState.heartRate)" : "—", unit: "BPM")
                    StatCard(label: "READINESS",
                             value: viewModel.sensorState.readinessScore > 0 ? "\(viewModel.sensorState.readinessScore)" : "—",
                             unit: viewModel.sensorState.readinessScore > 0 ? "/100" : "")
                }
                if viewModel.sensorState.readinessScore > 0 && !viewModel.sensorState.readinessBreakdown.isEmpty {
                    Text("Readiness: \(viewModel.sensorState.readinessBreakdown)")
                        .font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.textTertiary)
                }
                HStack(spacing: 10) {
                    StatCard(label: "STEPS",
                             value: viewModel.sensorState.stepsToday > 0 ? "\(viewModel.sensorState.stepsToday)" : "—",
                             unit: "Today")
                    StatCard(label: "ACTIVE",
                             value: viewModel.sensorState.activityMinutesToday > 0 ? "\(viewModel.sensorState.activityMinutesToday)" : "—",
                             unit: "MINS")
                }
                HStack(spacing: 10) {
                    StatCard(label: "KCAL",
                             value: viewModel.sensorState.caloriesBurned > 0 ? String(format: "%.0f", viewModel.sensorState.caloriesBurned) : "—",
                             unit: "BURNED")
                    StatCard(label: "SLEEP",
                             value: viewModel.sensorState.sleepScore > 0 ? "\(viewModel.sensorState.sleepScore)" : "—",
                             unit: viewModel.sensorState.sleepScore > 0 ? "/100" : "")
                }
                HStack(spacing: 10) {
                    StatCard(label: "WEATHER", value: viewModel.sensorState.weather, unit: "")
                    StatCard(label: "GPS",
                             value: String(format: "%.1f", viewModel.sensorState.speedKmh),
                             unit: "KM/H")
                }

                if !viewModel.currentMetricsContext.isEmpty && viewModel.playbackState != .idle {
                    Divider().padding(.vertical, 4)
                    AIReasoningPanel(
                        metricsContext: viewModel.currentMetricsContext,
                        mentalState: viewModel.currentMentalState,
                        songParams: viewModel.currentSongParams,
                    )
                }

                if !viewModel.songHistory.isEmpty {
                    Divider().padding(.vertical, 4)
                    Text("GENERATED TRACKS · \(viewModel.songHistory.count)")
                        .font(CadenceFont.labelMedium).foregroundStyle(CadenceColor.textSecondary)
                    ForEach(viewModel.songHistory.prefix(10)) { song in
                        GeneratedTrackCard(song: song)
                    }
                }

                Divider().padding(.vertical, 4)
                TasteProfileSection(memory: viewModel.tasteMemory, onClear: { viewModel.resetTasteMemory() })
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
    }
}

struct StatCard: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.textTertiary)
            HStack(alignment: .bottom, spacing: 3) {
                Text(value).font(CadenceFont.titleLarge).foregroundStyle(CadenceColor.textPrimary).bold()
                if !unit.isEmpty {
                    Text(unit).font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.textTertiary)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(CadenceColor.surface1))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

struct GeneratedTrackCard: View {
    let song: GeneratedSong

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(song.scene?.displayName ?? "—")
                .font(CadenceFont.labelSmall)
                .foregroundStyle(CadenceColor.sceneGlow(for: song.scene))
                .fontWeight(.bold)
                .frame(width: 72, alignment: .leading)
            Text(song.params.descriptions ?? "—")
                .font(CadenceFont.bodySmall)
                .foregroundStyle(CadenceColor.textPrimary)
                .lineLimit(2)
            Spacer()
            Text(timeAgo(song.generatedAt))
                .font(CadenceFont.labelSmall)
                .foregroundStyle(CadenceColor.textTertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }
}

struct TasteProfileSection: View {
    let memory: UserTasteMemory
    let onClear: () -> Void
    @State private var showClearConfirm = false

    var body: some View {
        HStack {
            Text("TASTE PROFILE").font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.textTertiary)
            Spacer()
            if memory.feedbackCount > 0 {
                Button("Reset memory") { showClearConfirm = true }
                    .font(CadenceFont.labelSmall)
                    .foregroundStyle(CadenceColor.errorRed.opacity(0.7))
            }
        }
        if showClearConfirm {
            HStack {
                Text("Wipe all \(memory.feedbackCount) signals?").font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.textTertiary)
                Spacer()
                Button("CONFIRM") { onClear(); showClearConfirm = false }
                    .font(CadenceFont.labelSmall)
                    .foregroundStyle(CadenceColor.errorRed)
                Button("Cancel") { showClearConfirm = false }
                    .font(CadenceFont.labelSmall)
                    .foregroundStyle(CadenceColor.textTertiary)
            }
        }
        if memory.feedbackCount == 0 {
            Text("Rate tracks to teach Cadence your taste.")
                .font(CadenceFont.bodySmall)
                .foregroundStyle(CadenceColor.textTertiary)
                .italic()
        } else {
            let topTags = memory.tagScores
                .sorted { $0.value > $1.value }
                .prefix(6)
            VStack(spacing: 8) {
                ForEach(Array(topTags), id: \.key) { tag, score in
                    HStack(spacing: 8) {
                        Text(tag).font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.textSecondary).frame(width: 80, alignment: .leading)
                        let fraction = Double((score + 1) / 2)
                        let color: Color = score >= 0.3 ? CadenceColor.feedbackLike : (score <= -0.3 ? CadenceColor.feedbackDislike : CadenceColor.textTertiary)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule().fill(color.opacity(0.7)).frame(width: geo.size.width * fraction)
                            }
                        }
                        .frame(height: 4)
                        Text(String(format: "%.0f%%", score * 100))
                            .font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.textTertiary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
        }
    }
}

func timeAgo(_ millis: Int64) -> String {
    let diff = Int64(Date().timeIntervalSince1970 * 1000) - millis
    let minutes = diff / 60_000
    if minutes < 1 { return "just now" }
    if minutes < 60 { return "\(minutes)m ago" }
    return "\(minutes / 60)h ago"
}
