import SwiftUI
import HealthKit
import CoreLocation
import Combine

struct PermissionsScreen: View {
    let onAllGranted: () -> Void

    @State private var locationGranted = false
    @State private var healthGranted = false
    @StateObject private var locationProbe = LocationAuthProbe()

    var body: some View {
        ZStack {
            CadenceColor.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                OnboardingTopBar(step: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("STEP 02 / PERMISSIONS")
                                .font(CadenceFont.labelMedium)
                                .foregroundStyle(CadenceColor.blue)
                            Spacer().frame(height: 10)
                            Text("Grant access to\nyour signals")
                                .font(CadenceFont.headlineLarge)
                                .foregroundStyle(CadenceColor.text)
                            Spacer().frame(height: 10)
                            Text("Cadence reads these locally on-device. Nothing is uploaded raw.")
                                .font(CadenceFont.bodyMedium)
                                .foregroundStyle(CadenceColor.textMute)
                        }
                        .padding(.horizontal, 28)
                        Spacer().frame(height: 20)
                        VStack(spacing: 12) {
                            PermissionRow(
                                icon: "heart.fill",
                                title: "Health & biosignals",
                                bodyText: "Heart rate, motion, sleep readiness. Drives BPM-matched generation.",
                                tag: .required,
                                granted: healthGranted,
                            ) {
                                Task {
                                    _ = try? await HealthKitPermissions.requestAuthorization()
                                    let granted = (await DIContainer.shared.sensorStateCollector.hasHeartRatePermission())
                                    await MainActor.run { healthGranted = granted }
                                }
                            }
                            PermissionRow(
                                icon: "location.fill",
                                title: "Location & motion",
                                bodyText: "Detects walking, running, transit. Lets the soundtrack switch with the scene.",
                                tag: .required,
                                granted: locationGranted,
                            ) {
                                locationProbe.request()
                            }
                            PermissionRow(
                                icon: "mic.fill",
                                title: "Microphone",
                                bodyText: "Sample ambient timbre to colour mixes. Audio never leaves the device.",
                                tag: .optional,
                                granted: false,
                            ) {}
                        }
                        .padding(.horizontal, 24)
                    }
                }
                PrimaryCadenceButton(
                    text: locationGranted ? "Continue" : "Allow & continue",
                    enabled: true,
                ) {
                    if locationGranted { onAllGranted() }
                    else { locationProbe.request() }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
            }
        }
        .onAppear { refreshStatus() }
        .onChange(of: locationProbe.status) { _ in refreshStatus() }
    }

    private func refreshStatus() {
        let status = locationProbe.status
        locationGranted = status == .authorizedWhenInUse || status == .authorizedAlways
        Task {
            let granted = await DIContainer.shared.sensorStateCollector.hasHeartRatePermission()
            await MainActor.run { healthGranted = granted }
        }
    }
}

private enum PermTag { case required, optional }

private struct PermissionRow: View {
    let icon: String
    let title: String
    let bodyText: String
    let tag: PermTag
    let granted: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(granted ? CadenceColor.bg : CadenceColor.textMute)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(granted ? CadenceColor.blue : Color.white.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(granted ? Color.clear : CadenceColor.border, lineWidth: 1))
                    )
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(CadenceFont.titleMedium)
                            .foregroundStyle(CadenceColor.text)
                        TagPill(tag: tag)
                    }
                    Text(bodyText)
                        .font(CadenceFont.bodySmall)
                        .foregroundStyle(CadenceColor.textMute)
                }
                Spacer()
                ToggleSwitch(checked: granted)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(granted ? CadenceColor.blueDim : CadenceColor.surface)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(granted ? CadenceColor.blue : CadenceColor.border, lineWidth: 1.5))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TagPill: View {
    let tag: PermTag
    var body: some View {
        let (txt, fg, bg, border): (String, Color, Color, Color) = {
            switch tag {
            case .required: return ("REQUIRED", CadenceColor.orange, CadenceColor.orangeDim, CadenceColor.orangeDimHi)
            case .optional: return ("OPTIONAL", CadenceColor.textMute, Color.white.opacity(0.06), .clear)
            }
        }()
        Text(txt)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(fg)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(bg))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(border, lineWidth: 1))
    }
}

private struct ToggleSwitch: View {
    let checked: Bool
    var body: some View {
        ZStack(alignment: checked ? .trailing : .leading) {
            Capsule()
                .fill(checked ? CadenceColor.blue : Color.white.opacity(0.12))
            Circle()
                .fill(Color.white)
                .frame(width: 18, height: 18)
                .padding(2)
        }
        .frame(width: 36, height: 22)
    }
}

final class LocationAuthProbe: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var status: CLAuthorizationStatus = .notDetermined
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        status = manager.authorizationStatus
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
    }
}
