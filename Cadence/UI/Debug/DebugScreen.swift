import SwiftUI

struct DebugScreen: View {
    @ObservedObject private var orchestrator = DIContainer.shared.musicOrchestrator!
    @ObservedObject private var sensorCollector = DIContainer.shared.sensorStateCollector!
    @State private var step1aStatus: String?

    var body: some View {
        ZStack {
            CadenceColor.surface0.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DEBUG").font(CadenceFont.titleLarge).foregroundStyle(CadenceColor.sceneGlow(for: nil))
                    section("Live Sensors")
                    row("Heart rate", sensorCollector.sensorState.heartRate > 0 ? "\(sensorCollector.sensorState.heartRate) bpm" : "—")
                    row("Speed", String(format: "%.1f km/h", sensorCollector.sensorState.speedKmh))

                    section("Health")
                    row("SpO2", sensorCollector.sensorState.spo2 > 0 ? "\(sensorCollector.sensorState.spo2)%" : "—")
                    row("BP", sensorCollector.sensorState.bloodPressureSystolic > 0
                        ? "\(sensorCollector.sensorState.bloodPressureSystolic)/\(sensorCollector.sensorState.bloodPressureDiastolic) mmHg" : "—")
                    row("Temp", sensorCollector.sensorState.bodyTemperature > 0
                        ? String(format: "%.1f°C", sensorCollector.sensorState.bodyTemperature) : "—")

                    section("Today")
                    row("Activity", "\(sensorCollector.sensorState.activityMinutesToday) mins")
                    row("Steps", sensorCollector.sensorState.stepsToday > 0 ? "\(sensorCollector.sensorState.stepsToday)" : "—")
                    row("Distance", sensorCollector.sensorState.distanceKm > 0
                        ? String(format: "%.2f km", sensorCollector.sensorState.distanceKm) : "—")
                    row("Floors", sensorCollector.sensorState.floorsClimbed > 0 ? "\(sensorCollector.sensorState.floorsClimbed)" : "—")
                    row("Calories", sensorCollector.sensorState.caloriesBurned > 0
                        ? String(format: "%.0f kcal", sensorCollector.sensorState.caloriesBurned) : "—")

                    section("Sleep")
                    row("Duration", sensorCollector.sensorState.sleepHours > 0
                        ? String(format: "%.1fh", sensorCollector.sensorState.sleepHours) : "—")
                    row("Deep / REM",
                        String(format: "%.0f%% / %.0f%%", sensorCollector.sensorState.sleepDeepPct, sensorCollector.sensorState.sleepRemPct))

                    section("Scene")
                    row("Raw", orchestrator.candidateScene?.displayName ?? "—")
                    row("Confirmed", orchestrator.currentScene?.displayName ?? "—")
                    row("Hour", "\(sensorCollector.sensorState.hourOfDay):00")

                    section("Mental State")
                    if let ms = DIContainer.shared.audioBufferManager.currentMentalState {
                        let valenceStr = ms.valence.map { $0 >= 0 ? "+\($0)" : "\($0)" } ?? "—"
                        row("Arousal / Valence", "\(ms.arousal.map(String.init) ?? "—")/10   \(valenceStr)/5")
                        row("Stress / Energy / Focus", "\(ms.stress.map(String.init) ?? "—")/10   \(ms.energy.map(String.init) ?? "—")/10   \(ms.focus.map(String.init) ?? "—")/10")
                        row("Mood", ms.mood ?? "—")
                    } else {
                        Text("(awaiting LLM)").font(CadenceFont.bodySmall).foregroundStyle(CadenceColor.textTertiary)
                    }

                    section("Step 1a Status")
                    Text(step1aStatus ?? "(no calls yet)")
                        .font(CadenceFont.bodySmall)
                        .foregroundStyle(CadenceColor.textPrimary)
                        .textSelection(.enabled)
                }
                .padding(24)
            }
        }
        .onReceive(DIContainer.shared.generationRepository.step1aStatusPublisher) { status in
            step1aStatus = status
        }
    }

    private func section(_ title: String) -> some View {
        Text("— \(title) —").font(CadenceFont.labelMedium).foregroundStyle(CadenceColor.textSecondary)
    }

    private func row(_ label: String, _ value: String) -> some View {
        Text("\(label): \(value)").font(CadenceFont.bodySmall).foregroundStyle(CadenceColor.textPrimary)
    }
}
