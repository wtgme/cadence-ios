import SwiftUI

enum CadenceButtonTone { case blue, orange }

struct PrimaryCadenceButton: View {
    let text: String
    var tone: CadenceButtonTone = .blue
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(CadenceFont.titleLarge)
                .foregroundStyle(enabled ? CadenceColor.bg : CadenceColor.textDim)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var background: some View {
        let colors: [Color] = {
            if !enabled { return [Color.white.opacity(0.06), Color.white.opacity(0.06)] }
            switch tone {
            case .orange: return [CadenceColor.orange, CadenceColor.orangeDeep]
            case .blue:   return [CadenceColor.blue, CadenceColor.blueDeep]
            }
        }()
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

struct GhostCadenceButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(CadenceFont.titleMedium)
                .foregroundStyle(CadenceColor.text)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(CadenceColor.borderHi, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
