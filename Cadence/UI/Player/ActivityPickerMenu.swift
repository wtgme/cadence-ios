import SwiftUI

/// Full sheet presentation matching the Settings screen's visual language —
/// dark surface, label-medium top bar title in Cadence orange, full-bleed list.
struct ActivityPickerMenu: View {
    let currentScene: Scene?
    let onSelect: (Scene) -> Void
    let onAutoDetect: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            CadenceColor.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Scene.allCases, id: \.self) { scene in
                            row(
                                label: scene.displayName,
                                icon: scene.iconName,
                                active: scene == currentScene,
                            ) {
                                onSelect(scene)
                            }
                        }
                        Spacer().frame(height: 8)
                        autoDetectRow
                    }
                    .padding(.horizontal, 24).padding(.vertical, 14)
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .foregroundStyle(CadenceColor.text)
                    .frame(width: 36, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
            Text("PICK ACTIVITY").font(CadenceFont.labelLarge).foregroundStyle(CadenceColor.orange)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    private func row(label: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(active ? CadenceColor.orange : CadenceColor.textMute)
                    .frame(width: 24)
                Text(label)
                    .font(CadenceFont.titleMedium)
                    .foregroundStyle(active ? CadenceColor.orange : CadenceColor.text)
                Spacer()
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CadenceColor.orange)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(active ? CadenceColor.orangeDim : CadenceColor.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(active ? CadenceColor.orangeDimHi : CadenceColor.border, lineWidth: 1),
                    ),
            )
        }
        .buttonStyle(.plain)
    }

    private var autoDetectRow: some View {
        Button(action: onAutoDetect) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(CadenceColor.blue)
                    .frame(width: 24)
                Text("Auto-detect")
                    .font(CadenceFont.titleMedium)
                    .foregroundStyle(CadenceColor.blue)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(CadenceColor.blueDim)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(CadenceColor.blueDimHi, lineWidth: 1),
                    ),
            )
        }
        .buttonStyle(.plain)
    }
}
