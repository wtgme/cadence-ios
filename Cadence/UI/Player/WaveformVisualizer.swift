import SwiftUI

/// Linear 32-bar waveform — animated when playing.
struct WaveformVisualizer: View {
    let isPlaying: Bool
    let bpm: Int
    var color: Color = .white

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { context in
            Canvas { ctx, size in
                let barCount = 32
                let barWidth = size.width / CGFloat(barCount * 2)
                let centerY = size.height / 2
                let maxAmp = size.height / 2 * 0.85
                let beatPeriod = bpm > 0 ? 60.0 / Double(bpm) : 0.6
                let phase = (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: beatPeriod)) / beatPeriod * 2 * .pi

                for i in 0..<barCount {
                    let x = CGFloat(i) * size.width / CGFloat(barCount) + barWidth
                    let amplitude: CGFloat
                    if isPlaying {
                        let s = (sin(phase + Double(i) * 0.4) + 1) / 2
                        amplitude = maxAmp * (0.4 + 0.6 * s)
                    } else {
                        amplitude = maxAmp * 0.1
                    }
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: centerY - amplitude))
                    path.addLine(to: CGPoint(x: x, y: centerY + amplitude))
                    ctx.stroke(path, with: .color(color.opacity(isPlaying ? 0.85 : 0.3)), style: StrokeStyle(lineWidth: barWidth * 0.7, lineCap: .round))
                }
            }
        }
    }
}

/// Circular radial-bar waveform shown in the hero.
struct CircularWaveformVisualizer: View {
    let isPlaying: Bool
    let bpm: Int
    let glowColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { context in
            Canvas { ctx, size in
                let cx = size.width / 2
                let cy = size.height / 2
                let outerR = min(size.width, size.height) / 2
                let center = CGPoint(x: cx, y: cy)

                // Outer hairline circle
                let outerRing = Path(ellipseIn: CGRect(x: cx - outerR * 0.84, y: cy - outerR * 0.84, width: outerR * 1.68, height: outerR * 1.68))
                ctx.stroke(outerRing, with: .color(.white.opacity(0.06)), lineWidth: 1)

                // Gradient progress arc
                let beatPeriod = bpm > 0 ? max(0.3, min(2.0, 60.0 / Double(bpm))) : 0.8
                let phase = (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: beatPeriod)) / beatPeriod * 2 * .pi
                let rotation = isPlaying ? phase * 0.5 : 0
                let arcR = outerR * 0.72
                let arcRect = CGRect(x: cx - arcR, y: cy - arcR, width: arcR * 2, height: arcR * 2)
                var arcPath = Path()
                arcPath.addArc(center: center, radius: arcR,
                               startAngle: .degrees(-100 + Angle.radians(rotation).degrees),
                               endAngle:   .degrees(180 + Angle.radians(rotation).degrees),
                               clockwise: false)
                ctx.stroke(arcPath, with: .linearGradient(
                    Gradient(colors: [CadenceColor.blue, CadenceColor.orange]),
                    startPoint: arcRect.origin,
                    endPoint: CGPoint(x: arcRect.maxX, y: arcRect.maxY),
                ), style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // Tick marks
                let tickCount = 48
                let activeTicks: Int = {
                    if !isPlaying { return 16 }
                    let sweep = ((sin(phase) + 1) / 2) * 8
                    return max(20, min(38, 28 + Int(sweep)))
                }()
                let tickInnerR = outerR * 0.50
                let tickOuterR = outerR * 0.56
                for i in 0..<tickCount {
                    let ang = (2 * .pi * Double(i) / Double(tickCount)) - .pi / 2
                    let active = i < activeTicks
                    let opacity = active ? (0.4 + (1 - Double(i) / Double(activeTicks)) * 0.6) : 0.12
                    let lineColor: Color = active ? glowColor.opacity(opacity) : .white.opacity(0.12)
                    var p = Path()
                    p.move(to: CGPoint(x: cx + cos(ang) * tickInnerR, y: cy + sin(ang) * tickInnerR))
                    p.addLine(to: CGPoint(x: cx + cos(ang) * tickOuterR, y: cy + sin(ang) * tickOuterR))
                    ctx.stroke(p, with: .color(lineColor), style: StrokeStyle(lineWidth: active ? 2 : 1.2, lineCap: .round))
                }
            }
        }
        .frame(width: 240, height: 240)
    }
}

/// Indeterminate progress arc shown while music is generating.
struct GenerationProgressArc: View {
    let generationStartMs: Int64
    let glowColor: Color

    @State private var elapsedSeconds = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            TimelineView(.animation) { context in
                Canvas { ctx, size in
                    let strokeW: CGFloat = 8
                    let inset = strokeW / 2
                    let rect = CGRect(x: inset, y: inset, width: size.width - strokeW, height: size.height - strokeW)
                    let center = CGPoint(x: rect.midX, y: rect.midY)
                    let radius = min(rect.width, rect.height) / 2

                    func drawArc(start: Double, sweep: Double, opacity: Double) {
                        var path = Path()
                        path.addArc(center: center, radius: radius,
                                    startAngle: .degrees(start),
                                    endAngle: .degrees(start + sweep),
                                    clockwise: false)
                        ctx.stroke(path, with: .color(glowColor.opacity(opacity)), style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                    }

                    // Background tracks
                    drawArc(start: 195, sweep: 150, opacity: 0.12)
                    drawArc(start: 15,  sweep: 150, opacity: 0.12)

                    let t = context.date.timeIntervalSinceReferenceDate
                    let pulse1 = 0.25 + 0.75 * (sin(t * 2.6) + 1) / 2
                    let pulse2 = 0.25 + 0.75 * (cos(t * 2.6) + 1) / 2
                    drawArc(start: 195, sweep: 150, opacity: 0.85 * pulse1)
                    drawArc(start: 15,  sweep: 150, opacity: 0.85 * pulse2)
                }
            }
            VStack(spacing: 4) {
                Text("Synthesising")
                    .font(CadenceFont.labelMedium)
                    .foregroundStyle(CadenceColor.textSecondary)
                Text("\(elapsedSeconds)s")
                    .font(CadenceFont.labelSmall)
                    .foregroundStyle(glowColor.opacity(0.6))
            }
        }
        .frame(width: 200, height: 200)
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
        .onChange(of: generationStartMs) { _ in startTimer() }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedSeconds = Int((Int64(Date().timeIntervalSince1970 * 1000) - generationStartMs) / 1000)
        }
        elapsedSeconds = 0
    }
}
