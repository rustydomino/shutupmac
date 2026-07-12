import Foundation

enum CLIInstallCommandBuilder {
    static func makeCommand() -> String {
        let cliPath = preferredCLIPath()

        return """
        mkdir -p "$HOME/.local/bin" && ln -sf \(shellQuote(cliPath)) "$HOME/.local/bin/shutupmac"
        """
    }

    private static func preferredCLIPath() -> String {
        let appURL = Bundle.main.bundleURL

        // Final/product location we probably want later:
        // ShutUpMac.app/Contents/Helpers/shutupmac
        let bundledHelperURL = appURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Helpers")
            .appendingPathComponent("shutupmac")

        if FileManager.default.isExecutableFile(atPath: bundledHelperURL.path) {
            return bundledHelperURL.path
        }

        // Development fallback:
        // Products/Debug/ShutUpMac.app
        // Products/Debug/shutupmac
        let siblingCLIURL = appURL
            .deletingLastPathComponent()
            .appendingPathComponent("shutupmac")

        if FileManager.default.isExecutableFile(atPath: siblingCLIURL.path) {
            return siblingCLIURL.path
        }

        // Default to the intended final bundle location.
        return bundledHelperURL.path
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
