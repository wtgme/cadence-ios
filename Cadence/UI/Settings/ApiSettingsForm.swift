import SwiftUI

/// Two-section form (Signal2Style + SongGen) reused by SettingsScreen and ApiSetupScreen.
struct ApiSettingsForm: View {
    @Binding var draft: ApiSettingsDraft
    let defaults: ApiSettings

    @State private var s2sKeyVisible = false
    @State private var sgKeyVisible = false

    var body: some View {
        VStack(spacing: 12) {
            section(
                step: "STEP 1", title: "Signal2Style", sub: "LLM",
                onReset: {
                    draft.signal2StyleBaseUrl = defaults.signal2StyleBaseUrl
                    draft.signal2StyleApiKey = defaults.signal2StyleApiKey
                    draft.signal2StyleModel = defaults.signal2StyleModel
                },
            ) {
                SettingField(label: "Base URL", value: $draft.signal2StyleBaseUrl, placeholder: defaults.signal2StyleBaseUrl)
                SecretField(label: "API key", value: $draft.signal2StyleApiKey, visible: $s2sKeyVisible)
                SettingField(label: "Model", value: $draft.signal2StyleModel, placeholder: defaults.signal2StyleModel)
            }
            section(
                step: "STEP 2", title: "SongGen", sub: "music",
                onReset: {
                    draft.songGenBaseUrl = defaults.songGenBaseUrl
                    draft.songGenApiKey = defaults.songGenApiKey
                    draft.songGenModel = defaults.songGenModel
                },
            ) {
                SettingField(label: "Base URL", value: $draft.songGenBaseUrl, placeholder: defaults.songGenBaseUrl)
                SecretField(label: "API key", value: $draft.songGenApiKey, visible: $sgKeyVisible)
                SettingField(label: "Model", value: $draft.songGenModel, placeholder: defaults.songGenModel)
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(step: String, title: String, sub: String, onReset: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(step).font(CadenceFont.labelMedium).foregroundStyle(CadenceColor.blue)
                Text(title).font(CadenceFont.titleMedium).foregroundStyle(CadenceColor.text)
                Text(sub).font(CadenceFont.labelMedium).foregroundStyle(CadenceColor.textMute)
            }
            VStack(spacing: 10) { content() }
            Button("Reset this section", action: onReset)
                .font(CadenceFont.labelMedium)
                .foregroundStyle(CadenceColor.orange)
                .padding(.vertical, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(CadenceColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CadenceColor.border, lineWidth: 1))
    }
}

private struct SettingField: View {
    let label: String
    @Binding var value: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(CadenceFont.labelMedium).foregroundStyle(CadenceColor.textMute)
            TextField(placeholder, text: $value)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(CadenceColor.text)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(CadenceColor.border, lineWidth: 1)
                )
        }
    }
}

private struct SecretField: View {
    let label: String
    @Binding var value: String
    @Binding var visible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(CadenceFont.labelMedium).foregroundStyle(CadenceColor.textMute)
            HStack {
                Group {
                    if visible {
                        TextField("(empty)", text: $value)
                    } else {
                        SecureField("(empty)", text: $value)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(CadenceColor.text)
                Button { visible.toggle() } label: {
                    Image(systemName: visible ? "eye.slash" : "eye")
                        .foregroundStyle(CadenceColor.textMute)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(CadenceColor.border, lineWidth: 1)
            )
        }
    }
}
