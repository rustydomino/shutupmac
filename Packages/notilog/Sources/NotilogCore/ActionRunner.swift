import Foundation

public enum ActionRunStatus: String, Equatable {
    case dryRun = "dry_run"
    case succeeded
    case uncertain
    case failed
}

public enum ActionVerificationStatus: String, Equatable {
    case pending
    case probablySucceeded = "probably_succeeded"
    case definitelyFailed = "definitely_failed"
}

public struct NotificationDismissalResult: Equatable {
    public let succeeded: Bool
    public let message: String
    public let exitCode: Int32

    public init(
        succeeded: Bool,
        message: String,
        exitCode: Int32
    ) {
        self.succeeded = succeeded
        self.message = message
        self.exitCode = exitCode
    }
}

public typealias NotificationDismissalHandler =
    (String) -> NotificationDismissalResult

public struct ActionRunResult {
    public let ruleName: String
    public let action: NotificationAction
    public let resolvedAction: ResolvedNotificationAction
    public let event: NotificationEvent
    public let status: ActionRunStatus
    public let message: String
    public let exitCode: Int32?
    public let stdout: String
    public let stderr: String
    public let verificationStatus: ActionVerificationStatus?

    public init(
        ruleName: String,
        action: NotificationAction,
        resolvedAction: ResolvedNotificationAction,
        event: NotificationEvent,
        status: ActionRunStatus,
        message: String,
        exitCode: Int32? = nil,
        stdout: String = "",
        stderr: String = "",
        verificationStatus: ActionVerificationStatus? = nil
    ) {
        self.ruleName = ruleName
        self.action = action
        self.resolvedAction = resolvedAction
        self.event = event
        self.status = status
        self.message = message
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
                self.verificationStatus = verificationStatus
    }
}

public final class ActionRunner {
    private let templateExpander: TemplateExpander
    private let dismissalHandler: NotificationDismissalHandler?

    public init(
        templateExpander: TemplateExpander = TemplateExpander(),
        dismissalHandler: NotificationDismissalHandler? = nil
    ) {
        self.templateExpander = templateExpander
        self.dismissalHandler = dismissalHandler
    }

    public func runDryRun(_ match: AutomationMatch) -> ActionRunResult {
        let resolvedAction = resolve(match.action, for: match.event)

        return ActionRunResult(
            ruleName: match.ruleName,
            action: match.action,
            resolvedAction: resolvedAction,
            event: match.event,
            status: .dryRun,
            message: dryRunMessage(for: resolvedAction)
        )
    }

    public func run(_ match: AutomationMatch) -> ActionRunResult {
        let resolvedAction = resolve(match.action, for: match.event)

        switch resolvedAction {
        case .dryRunLog(let message):
            return ActionRunResult(
                ruleName: match.ruleName,
                action: match.action,
                resolvedAction: resolvedAction,
                event: match.event,
                status: .succeeded,
                message: "logged: \(message)"
            )

        case .exec(let command, let arguments):
            return runExec(
                command: command,
                arguments: arguments,
                match: match,
                resolvedAction: resolvedAction
            )

        case .shutUpMacDismiss(let command, let notificationKey):
            return runShutUpMacDismiss(
                command: command,
                notificationKey: notificationKey,
                match: match,
                resolvedAction: resolvedAction,
            )
        }
    }

    public func resolve(
        _ action: NotificationAction,
        for event: NotificationEvent
    ) -> ResolvedNotificationAction {
        switch action {
        case .dryRunLog(let message):
            return .dryRunLog(
                message: templateExpander.expand(message, for: event)
            )

        case .exec(let command, let arguments):
            let expandedArguments = arguments.map {
                templateExpander.expand($0, for: event)
            }

            return .exec(
                command: command,
                arguments: expandedArguments
            )

        case .shutUpMacDismiss(let command):
            return .shutUpMacDismiss(
                command: command,
                notificationKey: event.notification.key
            )
        }
    }

    private func dryRunMessage(
        for resolvedAction: ResolvedNotificationAction
    ) -> String {
        switch resolvedAction {
        case .dryRunLog(let message):
            return "would log: \(message)"

        case .exec, .shutUpMacDismiss:
            return "would run: \(resolvedAction.summary)"
        }
    }

    private func runShutUpMacDismiss(
        command: String,
        notificationKey: String,
        match: AutomationMatch,
        resolvedAction: ResolvedNotificationAction
    ) -> ActionRunResult {
        if let dismissalHandler {
            return runInjectedDismissalHandler(
                notificationKey: notificationKey,
                match: match,
                resolvedAction: resolvedAction,
                handler: dismissalHandler
            )
        }

        let result = runExec(
            command: command,
            arguments: ["--dismiss-key", notificationKey],
            match: match,
            resolvedAction: resolvedAction,
            verificationStatusOnSuccess: .pending
        )

        guard result.status == .failed,
              result.stderr.contains(
                "Dismiss action was performed, but no visible progress was observed"
              ) else {
            return result
        }

        return ActionRunResult(
            ruleName: result.ruleName,
            action: result.action,
            resolvedAction: result.resolvedAction,
            event: result.event,
            status: .uncertain,
            message: "\(result.message); awaiting delayed verification",
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
            verificationStatus: .pending
        )
    }

    private func runInjectedDismissalHandler(
        notificationKey: String,
        match: AutomationMatch,
        resolvedAction: ResolvedNotificationAction,
        handler: NotificationDismissalHandler
    ) -> ActionRunResult {
        let result = handler(notificationKey)

        if !result.succeeded,
           result.message.contains(
               "Dismiss action was performed, but no visible progress was observed"
           ) {
            return ActionRunResult(
                ruleName: match.ruleName,
                action: match.action,
                resolvedAction: resolvedAction,
                event: match.event,
                status: .uncertain,
                message: "\(result.message); awaiting delayed verification",
                exitCode: result.exitCode,
                verificationStatus: .pending
            )
        }

        return ActionRunResult(
            ruleName: match.ruleName,
            action: match.action,
            resolvedAction: resolvedAction,
            event: match.event,
            status: result.succeeded ? .succeeded : .failed,
            message: result.message,
            exitCode: result.exitCode,
            verificationStatus: result.succeeded
                ? .probablySucceeded
                : .definitelyFailed
        )
    }

    private func runExec(
        command: String,
        arguments: [String],
        match: AutomationMatch,
        resolvedAction: ResolvedNotificationAction,
        verificationStatusOnSuccess: ActionVerificationStatus? = nil
    ) -> ActionRunResult {       
        guard command.hasPrefix("/") else {
            return ActionRunResult(
                ruleName: match.ruleName,
                action: match.action,
                resolvedAction: resolvedAction,
                event: match.event,
                status: .failed,
                message: "refusing to run non-absolute command path: \(command)"
            )
        }

        guard FileManager.default.isExecutableFile(atPath: command) else {
            return ActionRunResult(
                ruleName: match.ruleName,
                action: match.action,
                resolvedAction: resolvedAction,
                event: match.event,
                status: .failed,
                message: "command is not executable: \(command)"
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let exitCode = process.terminationStatus

            let status: ActionRunStatus = exitCode == 0 ? .succeeded : .failed

            return ActionRunResult(
                ruleName: match.ruleName,
                action: match.action,
                resolvedAction: resolvedAction,
                event: match.event,
                status: status,
                message: "ran: \(resolvedAction.summary) exited with \(exitCode)",
                exitCode: exitCode,
                stdout: stdout,
                stderr: stderr,
                verificationStatus: status == .succeeded
                    ? verificationStatusOnSuccess
                    : nil
            )
        } catch {
            return ActionRunResult(
                ruleName: match.ruleName,
                action: match.action,
                resolvedAction: resolvedAction,
                event: match.event,
                status: .failed,
                message: "failed to run: \(resolvedAction.summary): \(error.localizedDescription)"
            )
        }
    }
}
