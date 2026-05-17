import Foundation
import Combine

struct ApiSettingsDraft: Equatable {
    var signal2StyleBaseUrl: String
    var signal2StyleApiKey: String
    var signal2StyleModel: String
    var songGenBaseUrl: String
    var songGenApiKey: String
    var songGenModel: String

    static func from(_ s: ApiSettings) -> ApiSettingsDraft {
        ApiSettingsDraft(
            signal2StyleBaseUrl: s.signal2StyleBaseUrl,
            signal2StyleApiKey:  s.signal2StyleApiKey,
            signal2StyleModel:   s.signal2StyleModel,
            songGenBaseUrl:      s.songGenBaseUrl,
            songGenApiKey:       s.songGenApiKey,
            songGenModel:        s.songGenModel,
        )
    }
}

final class SettingsViewModel: ObservableObject {

    enum Result {
        case saved
        case invalid(String)
    }

    private let repo: ApiSettingsRepository
    @Published private(set) var settings: ApiSettings
    let defaults: ApiSettings

    private var cancellable: AnyCancellable?

    init(repo: ApiSettingsRepository = DIContainer.shared.apiSettingsRepository) {
        self.repo = repo
        self.settings = repo.settings
        self.defaults = repo.defaults
        cancellable = repo.$settings.sink { [weak self] s in self?.settings = s }
    }

    func save(draft: ApiSettingsDraft, onResult: @escaping (Result) -> Void) {
        if let err = validateUrl(draft.signal2StyleBaseUrl, label: "Signal2Style base URL") {
            onResult(.invalid(err)); return
        }
        if let err = validateUrl(draft.songGenBaseUrl, label: "SongGen base URL") {
            onResult(.invalid(err)); return
        }
        let s = ApiSettings(
            signal2StyleBaseUrl: draft.signal2StyleBaseUrl.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: .init(charactersIn: "/")),
            signal2StyleApiKey:  draft.signal2StyleApiKey.trimmingCharacters(in: .whitespaces),
            signal2StyleModel:   draft.signal2StyleModel.trimmingCharacters(in: .whitespaces),
            songGenBaseUrl:      draft.songGenBaseUrl.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: .init(charactersIn: "/")),
            songGenApiKey:       draft.songGenApiKey.trimmingCharacters(in: .whitespaces),
            songGenModel:        draft.songGenModel.trimmingCharacters(in: .whitespaces),
        )
        repo.save(s)
        onResult(.saved)
    }

    func resetAll() {
        repo.resetAll()
    }

    private func validateUrl(_ value: String, label: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "\(label) cannot be empty" }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return "\(label) is not a valid URL"
        }
        if !["http", "https"].contains(scheme) {
            return "\(label) must start with http:// or https://"
        }
        return nil
    }
}
