import Combine
import Foundation
import NotilogCore

@MainActor
final class AutomationConfigurationStore:
    ObservableObject {

    @Published private(set)
    var configuration: AutomationConfig?

    @Published private(set)
    var errorMessage: String?

    let configURL: URL

    init(configURL: URL) {
        self.configURL = configURL
    }

    @discardableResult
    func load() -> AutomationConfig? {
        guard FileManager.default.fileExists(
            atPath: configURL.path
        ) else {
            let emptyConfiguration =
                AutomationConfig(rules: [])
            
            configuration = emptyConfiguration
            errorMessage = nil

            return emptyConfiguration

        }

        do {
            let candidate =
                try AutomationConfig.load(
                    from: configURL
                )

            // Decoding valid JSON is not enough. Converting
            // every configured rule also catches invalid actions
            // such as an exec action with no command.
            _ = try candidate.notificationRules()

            configuration = candidate
            errorMessage = nil

            return candidate
        } catch {
            // Deliberately do not clear configuration here.
            // A failed reload must preserve the last valid value.
            errorMessage = String(
                describing: error
            )

            return nil
        }
    }

    func activate(
        _ candidate: AutomationConfig,
        using controller: NotilogMonitoringController
    ) {
        do {
            // Reject invalid rules before sending the candidate
            // to the monitoring runtime.
            _ = try candidate.notificationRules()
        } catch {
            errorMessage = String(
                describing: error
            )

            return
        }

        controller.replaceAutomationConfiguration(
            candidate
        ) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .activated:
                configuration = candidate
                errorMessage = nil

            case .failed(let message):
                // Preserve the previously active configuration.
                errorMessage = message
            }
        }
    }

}
