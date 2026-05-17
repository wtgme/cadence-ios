import SwiftUI

struct AIReasoningPanel: View {
    let metricsContext: String
    let mentalState: MentalState?
    let songParams: SongParams?
    @State private var expanded = false

    var body: some View {
        Button(action: { expanded.toggle() }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("AI REASONING CHAIN")
                        .font(CadenceFont.labelMedium)
                        .foregroundStyle(CadenceColor.textSecondary)
                    Spacer()
                    Text(expanded ? "collapse" : "expand")
                        .font(CadenceFont.labelSmall)
                        .foregroundStyle(CadenceColor.sceneGlow(for: nil).opacity(0.6))
                }
                Spacer().frame(height: 12)
                sectionTitle("INPUT: BIOMETRIC CONTEXT")
                Spacer().frame(height: 4)
                Text(metricsContext)
                    .font(CadenceFont.bodySmall)
                    .foregroundStyle(CadenceColor.textSecondary)
                    .lineLimit(expanded ? nil : 3)
                Divider().padding(.vertical, 10)
                sectionTitle("ESTIMATION: MENTAL STATE")
                Spacer().frame(height: 6)
                if let ms = mentalState {
                    MentalStateRow(ms: ms)
                } else {
                    ProgressView().tint(CadenceColor.sceneGlow(for: nil))
                }
                Divider().padding(.vertical, 10)
                sectionTitle("RECOMMENDATION: MUSIC STYLES")
                Spacer().frame(height: 6)
                if let params = songParams {
                    Text("Style: \(params.descriptions ?? "none")")
                        .font(CadenceFont.bodySmall)
                        .foregroundStyle(CadenceColor.textPrimary)
                        .fontWeight(.semibold)
                        .lineLimit(expanded ? nil : 1)
                    Spacer().frame(height: 6)
                    Text("Lyrics:")
                        .font(CadenceFont.labelSmall)
                        .foregroundStyle(CadenceColor.textTertiary)
                    Text(params.lyric)
                        .font(CadenceFont.bodySmall)
                        .foregroundStyle(CadenceColor.textSecondary)
                        .italic()
                        .lineLimit(expanded ? nil : 3)
                    if expanded {
                        Divider().padding(.vertical, 6)
                        Text("type = \(params.generateType)")
                            .font(CadenceFont.bodySmall).foregroundStyle(CadenceColor.textSecondary)
                        Text("auto_prompt = \(params.autoPromptAudioType ?? "none")")
                            .font(CadenceFont.bodySmall).foregroundStyle(CadenceColor.textSecondary)
                    }
                } else {
                    ProgressView().tint(CadenceColor.sceneGlow(for: nil))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LinearGradient(colors: [.white.opacity(0.1), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(CadenceFont.labelSmall)
            .foregroundStyle(CadenceColor.sceneGlow(for: nil))
            .fontWeight(.bold)
    }
}

struct MentalStateRow: View {
    let ms: MentalState

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                mentalMetricBar(label: "AROUSAL", value: ms.arousal, max: 10, color: CadenceColor.orange)
                valenceBar(value: ms.valence)
                mentalMetricBar(label: "STRESS",  value: ms.stress,  max: 10, color: CadenceColor.feedbackDislike)
            }
            HStack {
                mentalMetricBar(label: "ENERGY", value: ms.energy, max: 10, color: Color(hex: 0x56C96D))
                mentalMetricBar(label: "FOCUS",  value: ms.focus,  max: 10, color: CadenceColor.blue)
                VStack {
                    Text("MOOD").font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.textTertiary)
                    Text(ms.mood ?? "—").font(CadenceFont.bodySmall).italic().foregroundStyle(CadenceColor.textSecondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func mentalMetricBar(label: String, value: Int?, max: Int = 10, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label).font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.textTertiary)
            if let v = value {
                HStack(spacing: 2) {
                    ForEach(1...max, id: \.self) { i in
                        Circle().fill(i <= v ? color.opacity(0.85) : color.opacity(0.15))
                            .frame(width: 5, height: 5)
                    }
                }
                Text("\(v)").font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.textSecondary)
            } else {
                Text("—").font(CadenceFont.bodySmall).foregroundStyle(CadenceColor.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func valenceBar(value: Int?) -> some View {
        VStack(spacing: 3) {
            Text("VALENCE").font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.textTertiary)
            if let v = value {
                HStack(spacing: 2) {
                    ForEach((-5)...(-1), id: \.self) { i in
                        Circle().fill(v <= i ? CadenceColor.feedbackDislike.opacity(0.85) : CadenceColor.feedbackDislike.opacity(0.15))
                            .frame(width: 5, height: 5)
                    }
                    Spacer().frame(width: 2)
                    ForEach(1...5, id: \.self) { i in
                        Circle().fill(v >= i ? CadenceColor.feedbackLike.opacity(0.85) : CadenceColor.feedbackLike.opacity(0.15))
                            .frame(width: 5, height: 5)
                    }
                }
                let valenceStr = v >= 0 ? "+\(v)" : "\(v)"
                Text(valenceStr).font(CadenceFont.labelSmall).foregroundStyle(CadenceColor.textSecondary)
            } else {
                Text("—").font(CadenceFont.bodySmall).foregroundStyle(CadenceColor.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
