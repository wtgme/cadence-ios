import SwiftUI

struct StepDots: View {
    let step: Int
    var total: Int = 5

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                let active = i == step
                let past = i < step
                Capsule()
                    .fill(active ? CadenceColor.orange :
                          past   ? CadenceColor.blue :
                                   Color.white.opacity(0.16))
                    .frame(width: active ? 22 : 6, height: 4)
                    .animation(.easeInOut(duration: 0.2), value: active)
            }
        }
    }
}

struct OnboardingTopBar: View {
    let step: Int
    var totalSteps: Int = 5
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CadenceColor.textMute)
                        .frame(width: 36, height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CadenceColor.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
            Spacer()
            StepDots(step: step, total: totalSteps)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

struct CadenceMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32)
                .fill(AngularGradient(
                    colors: [CadenceColor.blue, CadenceColor.orange, CadenceColor.blue],
                    center: .center,
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.32)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                )
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(CadenceColor.bg)
                .padding(size * 0.14)
                .overlay(CadenceWaveform(maxBarHeight: size * 0.42))
        }
        .frame(width: size, height: size)
    }
}

private struct CadenceWaveform: View {
    let maxBarHeight: CGFloat

    private let heights: [CGFloat] = [0.4, 0.85, 0.55, 1.0, 0.55, 0.85, 0.4]
    private let colors: [Color] = [
        CadenceColor.blue, CadenceColor.blue, CadenceColor.blue,
        Color.white,
        CadenceColor.orange, CadenceColor.orange, CadenceColor.orange,
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<heights.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(colors[i])
                    .frame(width: 2.5, height: maxBarHeight * heights[i])
            }
        }
    }
}
