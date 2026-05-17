import SwiftUI

struct ActivityPickerMenu: View {
    let currentScene: Scene?
    let onSelect: (Scene) -> Void
    let onAutoDetect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PICK ACTIVITY")
                .font(CadenceFont.labelMedium)
                .foregroundStyle(CadenceColor.textMute)
                .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 6)
            ForEach(Scene.allCases, id: \.self) { scene in
                row(label: scene.displayName, icon: scene.iconName, active: scene == currentScene) {
                    onSelect(scene)
                }
            }
            Spacer().frame(height: 4)
            Divider().background(CadenceColor.border).padding(.horizontal, 8)
            Spacer().frame(height: 4)
            Button(action: onAutoDetect) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(CadenceColor.blue)
                    Text("Auto-detect")
                        .font(CadenceFont.titleSmall)
                        .foregroundStyle(CadenceColor.blue)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .frame(width: 228)
        .background(RoundedRectangle(cornerRadius: 16).fill(CadenceColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CadenceColor.borderHi, lineWidth: 1))
    }

    private func row(label: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(active ? CadenceColor.orange : CadenceColor.textMute)
                Text(label)
                    .font(CadenceFont.titleSmall)
                    .foregroundStyle(active ? CadenceColor.orange : CadenceColor.text)
                Spacer()
                if active {
                    Image(systemName: "checkmark")
                        .foregroundStyle(CadenceColor.orange)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(active ? CadenceColor.orangeDim : .clear))
        }
        .buttonStyle(.plain)
    }
}
