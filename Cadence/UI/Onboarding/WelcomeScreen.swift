import SwiftUI

struct WelcomeScreen: View {
    let onGetStarted: () -> Void

    var body: some View {
        ZStack {
            CadenceColor.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                BiometricRing()
                Spacer().frame(height: 28)
                Text("C · A · D · E · N · C · E")
                    .font(CadenceFont.labelLarge)
                    .foregroundStyle(CadenceColor.orange)
                Spacer().frame(height: 14)
                heroText
                    .multilineTextAlignment(.center)
                Spacer().frame(height: 14)
                Text("Generative tracks tuned in real time to your heart rate, motion and surroundings.")
                    .font(CadenceFont.bodyLarge)
                    .foregroundStyle(CadenceColor.textMute)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer()
                PrimaryCadenceButton(text: "Get started", action: onGetStarted)
                    .padding(.horizontal, 28)
            }
            .padding(.vertical, 24)
        }
    }

    private var heroText: Text {
        // `.foregroundStyle` on `Text` (returning `Text` for concatenation) is iOS 17+.
        // Use `.foregroundColor` for iOS 16 compatibility.
        Text("Music that\nmoves with ")
            .font(CadenceFont.displayLarge)
            .foregroundColor(CadenceColor.text) +
        Text("you")
            .font(CadenceFont.displayLarge)
            .foregroundColor(CadenceColor.orange) +
        Text(".")
            .font(CadenceFont.displayLarge)
            .foregroundColor(CadenceColor.text)
    }
}

private struct BiometricRing: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(CadenceColor.blueDimHi, lineWidth: 1)
                .frame(width: 220, height: 220)
            Circle()
                .stroke(CadenceColor.orangeDim, lineWidth: 1)
                .frame(width: 184, height: 184)
            Circle()
                .fill(RadialGradient(
                    colors: [CadenceColor.blueDimHi, .clear],
                    center: .center,
                    startRadius: 10,
                    endRadius: 72,
                ))
                .frame(width: 144, height: 144)
            Circle()
                .trim(from: 0, to: 0.64)
                .stroke(
                    LinearGradient(colors: [CadenceColor.blue, CadenceColor.orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round),
                )
                .rotationEffect(.degrees(-90))
                .padding(32)
                .frame(width: 220, height: 220)
            CadenceMark(size: 92)
        }
    }
}
