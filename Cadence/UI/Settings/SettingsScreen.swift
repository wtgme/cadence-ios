import SwiftUI

struct SettingsScreen: View {
    let onBack: () -> Void

    @StateObject private var viewModel = SettingsViewModel()
    @State private var draft: ApiSettingsDraft
    @State private var snackbar: String?

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
        _draft = State(initialValue: ApiSettingsDraft.from(DIContainer.shared.apiSettingsRepository.current))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            CadenceColor.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(CadenceColor.text)
                            .frame(width: 36, height: 36)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("API SETTINGS").font(CadenceFont.labelLarge).foregroundStyle(CadenceColor.orange)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            Text("Override defaults from ")
                                .font(CadenceFont.bodyMedium).foregroundStyle(CadenceColor.textMute)
                            Text("local.properties")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(CadenceColor.text)
                        }
                        Text("Changes take effect on the next generation.")
                            .font(CadenceFont.bodyMedium).foregroundStyle(CadenceColor.textMute)

                        Spacer().frame(height: 18)
                        ApiSettingsForm(draft: $draft, defaults: viewModel.defaults)
                        Spacer().frame(height: 8)

                        // Info banner
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(CadenceColor.blue)
                            Text("Keys are stored locally in UserDefaults and never sync to Cadence servers.")
                                .font(CadenceFont.bodyMedium).foregroundStyle(CadenceColor.text)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(CadenceColor.blueDim))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CadenceColor.blueDimHi, lineWidth: 1))

                        Spacer().frame(height: 18)
                        PrimaryCadenceButton(text: "Save") { save() }
                        Spacer().frame(height: 10)
                        Button("Reset all to defaults") {
                            viewModel.resetAll()
                            draft = ApiSettingsDraft.from(viewModel.defaults)
                            toast("All settings reset to defaults")
                        }
                        .foregroundStyle(CadenceColor.orange)
                        .font(CadenceFont.titleMedium)
                        .padding(.vertical, 12)
                        Spacer().frame(height: 24)
                    }
                    .padding(.horizontal, 24).padding(.vertical, 14)
                }
            }
            if let snackbar {
                Text(snackbar)
                    .font(CadenceFont.bodyMedium)
                    .foregroundStyle(CadenceColor.text)
                    .padding()
                    .background(CadenceColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(16)
                    .transition(.opacity)
            }
        }
    }

    private func save() {
        viewModel.save(draft: draft) { result in
            switch result {
            case .saved: toast("Saved")
            case .invalid(let msg): toast(msg)
            }
        }
    }

    private func toast(_ msg: String) {
        snackbar = msg
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { snackbar = nil }
        }
    }
}
