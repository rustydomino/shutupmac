import Foundation
import NotilogCore

enum CLIActionExecutionMode: Equatable {
    case disabled
    case dryRun
    case runActions

    var dryRunEnabled: Bool {
        self == .dryRun
    }

    var runActionsEnabled: Bool {
        self == .runActions
    }
}

/// Runtime policy selected by the notilog command-line host.
///
/// NotilogCore should receive these decisions rather than discovering them
/// through command-line arguments or process-global state.
struct CLIStartupConfiguration {
    let runtimePaths: NotilogRuntimePaths
    let configURL: URL

    let loggingEnabled: Bool
    let redactionPolicy: RedactionPolicy
    let actionExecutionMode: CLIActionExecutionMode

    let scanInterval: TimeInterval
    let dismissalVerificationDelay: TimeInterval

    let quietEnabled: Bool
    let debugEnabled: Bool
}