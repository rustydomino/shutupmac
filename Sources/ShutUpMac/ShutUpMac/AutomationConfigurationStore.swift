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

    private enum ConfigurationFileSnapshot {
        case missing
        case contents(Data)
    }

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

    func reloadFromDisk(
        using controller:
            any AutomationConfigurationActivating
    ) {
        let candidate: AutomationConfig

        do {
            if FileManager.default.fileExists(
                atPath: configURL.path
            ) {
                candidate = try AutomationConfig.load(
                    from: configURL
                )
            } else {
                candidate = AutomationConfig(
                    rules: []
                )
            }

            // Validate before asking the running monitor
            // to replace its current engine.
            _ = try candidate.notificationRules()
        } catch {
            // Preserve the currently active configuration.
            errorMessage = String(
                describing: error
            )

            return
        }

        activate(
            candidate,
            using: controller
        )
    }

    func writeConfiguration(
        _ candidate: AutomationConfig
    ) throws {
        // Validate the complete candidate before touching
        // the existing configuration file.
        _ = try candidate.notificationRules()

        let directoryURL =
            configURL.deletingLastPathComponent()

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes
        ]

        let data = try encoder.encode(candidate)

        try data.write(
            to: configURL,
            options: .atomic
        )
    }

    func activate(
        _ candidate: AutomationConfig,
        using controller:
            any AutomationConfigurationActivating
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

    func saveAndActivate(
        _ candidate: AutomationConfig,
        using controller:
            any AutomationConfigurationActivating
    ) {
        let snapshot: ConfigurationFileSnapshot

        do {
            snapshot = try captureConfigurationFile()

            try writeConfiguration(
                candidate
            )
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

            case .failed(let activationMessage):
                do {
                    try restoreConfigurationFile(
                        snapshot
                    )

                    // The old runtime configuration remained active,
                    // and its previous file representation is restored.
                    errorMessage = activationMessage
                } catch {
                    errorMessage =
                        activationMessage
                        + "\n\nAdditionally, config.json "
                        + "could not be restored: "
                        + String(describing: error)
                }
            }
        }
    }

    private func captureConfigurationFile()
        throws -> ConfigurationFileSnapshot {

        guard FileManager.default.fileExists(
            atPath: configURL.path
        ) else {
            return .missing
        }

        return .contents(
            try Data(contentsOf: configURL)
        )
    }

    private func restoreConfigurationFile(
        _ snapshot: ConfigurationFileSnapshot
    ) throws {
        switch snapshot {
        case .missing:
            guard FileManager.default.fileExists(
                atPath: configURL.path
            ) else {
                return
            }

            try FileManager.default.removeItem(
                at: configURL
            )

        case .contents(let data):
            let directoryURL =
                configURL.deletingLastPathComponent()

            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            try data.write(
                to: configURL,
                options: .atomic
            )
        }
    }    

}
