import SwiftUI

struct ReadyScreen: View {
    let onStartListening: () -> Void

    var body: some View {
        ZStack {
            CadenceColor.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                OnboardingTopBar(step: 4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        LivePreviewCard(title: "Morning Drift", subtitle: "seeded from your taste · 92 BPM")
                        Spacer().frame(height: 22)
                        Text("YOUR PROFILE")
                            .font(CadenceFont.labelMedium)
                            .foregroundStyle(CadenceColor.textMute)
                        Spacer().frame(height: 12)
                        VStack(spacing: 10) {
                            ProfileRow(label: "Signal source", value: "HealthKit",       dot: CadenceColor.blue)
                            ProfileRow(label: "Resting HR",    value: "calibrating",     dot: CadenceColor.orange)
                            ProfileRow(label: "Default scene", value: "auto-detect",     dot: CadenceColor.blue)
                            ProfileRow(label: "Pipeline",      value: "biometric → style → song", dot: CadenceColor.orange)
                        }
                    }
                    .padding(.horizontal, 28)
                }
                VStack(spacing: 14) {
                    Text("Your first track may take a minute to warm up\nwhile we calibrate.")
                        .font(CadenceFont.bodySmall)
                        .foregroundStyle(CadenceColor.textDim)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    PrimaryCadenceButton(text: "Start listening", tone: .orange, action: onStartListening)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
            }
        }
    }
}

private struct LivePreviewCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(CadenceColor.orangeDim).frame(width: 16, height: 16)
                    Circle().fill(CadenceColor.orange).frame(width: 8, height: 8)
                }
                Text("LIVE PREVIEW")
                    .font(CadenceFont.labelMedium)
                    .foregroundStyle(CadenceColor.orange)
            }
            Spacer().frame(height: 14)
            Text(title)
                .font(CadenceFont.displaySmall)
                .foregroundStyle(CadenceColor.text)
            Spacer().frame(height: 4)
            Text(subtitle)
                .font(CadenceFont.bodySmall)
                .foregroundStyle(CadenceColor.textMute)
            Spacer().frame(height: 18)
            staticWaveform
            Spacer().frame(height: 8)
            HStack {
                Text("0:42").foregroundStyle(CadenceColor.textDim).font(CadenceFont.labelSmall)
                Spacer()
                Text("∞").foregroundStyle(CadenceColor.textDim).font(CadenceFont.labelSmall)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [CadenceColor.surfaceHi, CadenceColor.surface], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(CadenceColor.border, lineWidth: 1))
        )
    }

    private var staticWaveform: some View {
        let bars = 42
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<bars, id: \.self) { i in
                let h = 0.25 + 0.75 * abs(sin(Double(i) * 0.55) * cos(Double(i) * 0.18))
                let past = i < 18
                RoundedRectangle(cornerRadius: 2)
                    .fill(past ? CadenceColor.orange : Color.white.opacity(0.18))
                    .frame(height: 48 * h)
            }
        }
        .frame(height: 48)
    }
}

private struct ProfileRow: View {
    let label: String
    let value: String
    let dot: Color

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(label).font(CadenceFont.bodySmall).foregroundStyle(CadenceColor.textMute)
            Spacer()
            Text(value).font(CadenceFont.titleSmall).foregroundStyle(CadenceColor.text)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(CadenceColor.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CadenceColor.border, lineWidth: 1))
        )
    }
}
