import SwiftUI

struct ApiSetupScreen: View {
    var isFirstRun: Bool = false
    let onSaveAndContinue: () -> Void

    @StateObject private var viewModel = SettingsViewModel()
    @State private var draft: ApiSettingsDraft
    @State private var snackbar: String?

    init(isFirstRun: Bool = false, onSaveAndContinue: @escaping () -> Void) {
        self.isFirstRun = isFirstRun
        self.onSaveAndContinue = onSaveAndContinue
        _draft = State(initialValue: ApiSettingsDraft.from(DIContainer.shared.apiSettingsRepository.current))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            CadenceColor.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                OnboardingTopBar(step: 2)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("STEP 03 / API SETUP")
                            .font(CadenceFont.labelMedium)
                            .foregroundStyle(CadenceColor.blue)
                        Spacer().frame(height: 10)
                        Text("Bring your\nown keys")
                            .font(CadenceFont.headlineLarge)
                            .foregroundStyle(CadenceColor.text)
                        Spacer().frame(height: 10)
                        Text("Cadence ships with shared default endpoints so you can try it immediately — but you'll get faster, more reliable generation with your own.")
                            .font(CadenceFont.bodyMedium)
                            .foregroundStyle(CadenceColor.textMute)
                        Spacer().frame(height: 20)
                        warningBanner
                        Spacer().frame(height: 18)
                        ApiSettingsForm(draft: $draft, defaults: viewModel.defaults)
                        Spacer().frame(height: 18)
                        PrimaryCadenceButton(text: "Save & continue") { save() }
                        Spacer().frame(height: 14)
                        Text("You can change these anytime from Settings (top-right of the player).")
                            .font(CadenceFont.bodySmall)
                            .foregroundStyle(CadenceColor.textMute)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Spacer().frame(height: 24)
                    }
                    .padding(.horizontal, 28)
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

    private var warningBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CadenceColor.orange)
                .padding(.top, 1)
            Text("The default endpoints use the developer's personal account. They can be slow or rate-limited under load. We recommend using your own keys.")
                .font(CadenceFont.bodyMedium)
                .foregroundStyle(CadenceColor.text)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(CadenceColor.orangeDim))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CadenceColor.orangeDimHi, lineWidth: 1))
    }

    private func save() {
        viewModel.save(draft: draft) { result in
            switch result {
            case .saved: onSaveAndContinue()
            case .invalid(let msg): showToast(msg)
            }
        }
    }

    private func showToast(_ msg: String) {
        snackbar = msg
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { snackbar = nil }
        }
    }
}
