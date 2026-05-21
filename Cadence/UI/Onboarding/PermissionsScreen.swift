import SwiftUI
import HealthKit
import CoreLocation
import Combine
import UserNotifications

struct PermissionsScreen: View {
    let onAllGranted: () -> Void

    @State private var locationGranted = false
    @State private var healthGranted = false
    @State private var healthError: String?
    @State private var healthRequesting = false
    @State private var notificationsGranted = false
    @State private var notificationsRequesting = false
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
                                loading: healthRequesting,
                            ) {
                                if healthRequesting { return }
                                // iOS doesn't allow apps to revoke their own permissions.
                                // Once granted, deep-link to iOS Settings so the user can
                                // toggle off there.
                                if healthGranted {
                                    openAppSettings()
                                    return
                                }
                                healthRequesting = true
                                Task { @MainActor in
                                    defer { healthRequesting = false }
                                    do {
                                        _ = try await HealthKitPermissions.requestAuthorization()
                                    } catch {
                                        healthError = error.localizedDescription
                                        return
                                    }
                                    healthGranted = await DIContainer.shared.sensorStateCollector.hasHeartRatePermission()
                                }
                            }
                            PermissionRow(
                                icon: "location.fill",
                                title: "Location & motion",
                                bodyText: "Detects walking, running, transit for richer scene switching and local weather context. Cadence still works without it — heart rate alone drives generation.",
                                tag: .optional,
                                granted: locationGranted,
                            ) {
                                if locationGranted {
                                    openAppSettings()
                                } else {
                                    locationProbe.request()
                                }
                            }
                            PermissionRow(
                                icon: "mic.fill",
                                title: "Microphone",
                                bodyText: "Sample ambient timbre to colour mixes. Audio never leaves the device.",
                                tag: .optional,
                                granted: false,
                            ) { openAppSettings() }
                            PermissionRow(
                                icon: "bell.fill",
                                title: "Notifications",
                                bodyText: "Background playback controls and session reminders.",
                                tag: .optional,
                                granted: notificationsGranted,
                                loading: notificationsRequesting,
                            ) {
                                if notificationsRequesting { return }
                                if notificationsGranted {
                                    openAppSettings()
                                    return
                                }
                                notificationsRequesting = true
                                Task { @MainActor in
                                    defer { notificationsRequesting = false }
                                    let granted = (try? await UNUserNotificationCenter.current()
                                        .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                                    notificationsGranted = granted
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                PrimaryCadenceButton(
                    text: "Continue",
                    enabled: true,
                ) {
                    onAllGranted()
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
            }
        }
        .onAppear { refreshStatus() }
        .onChange(of: locationProbe.status) { _ in refreshStatus() }
        // When the user returns from iOS Settings (e.g. after toggling a permission off),
        // re-probe so the UI reflects the new state.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
        .alert("Health access failed", isPresented: .constant(healthError != nil), actions: {
            Button("OK") { healthError = nil }
        }, message: {
            Text(
                (healthError ?? "")
                + "\n\nMake sure the HealthKit capability is added in Xcode → Signing & Capabilities."
            )
        })
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func refreshStatus() {
        let status = locationProbe.status
        locationGranted = status == .authorizedWhenInUse || status == .authorizedAlways
        Task {
            let granted = await DIContainer.shared.sensorStateCollector.hasHeartRatePermission()
            await MainActor.run { healthGranted = granted }
        }
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsGranted = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral
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
    var loading: Bool = false
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
                if loading {
                    ProgressView()
                        .tint(CadenceColor.blue)
                        .frame(width: 36, height: 22)
                } else {
                    ToggleSwitch(checked: granted)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(granted ? CadenceColor.blueDim : CadenceColor.surface)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(granted ? CadenceColor.blue : CadenceColor.border, lineWidth: 1.5))
            )
            .opacity(loading ? 0.85 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(loading)
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
