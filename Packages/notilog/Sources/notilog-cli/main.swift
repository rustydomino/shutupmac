import Foundation
import NotilogCore

let arguments = Array(CommandLine.arguments.dropFirst())

let runtimePaths = NotilogRuntimePaths.legacyNotilogDefault()

let quietEnabled = arguments.contains("--quiet")
let debugEnabled = arguments.contains("--debug") && !quietEnabled

let diagnosticHandler: DiagnosticHandler?

if debugEnabled {
    diagnosticHandler = { message in
        let data = Data("[debug] \(message)\n".utf8)
        FileHandle.standardError.write(data)
    }
} else {
    diagnosticHandler = nil
}

diagnosticHandler?("Debug logging enabled")

if arguments.contains("-v") || arguments.contains("--version") {
    print(notilogVersion)
    exit(0)
}

let command = arguments.first { !$0.hasPrefix("-") } ?? "help"

let dryRunActionsEnabled = arguments.contains("--dry-run-actions")
let runActionsEnabled = arguments.contains("--run-actions")
let loggingEnabled = !arguments.contains("--no-logging")

let shutUpMacVerificationDelay: TimeInterval = 2.0

if dryRunActionsEnabled, runActionsEnabled {
    fputs("Use either --dry-run-actions or --run-actions, not both.\n", stderr)
    exit(2)
}

let actionExecutionMode: CLIActionExecutionMode

if dryRunActionsEnabled {
    actionExecutionMode = .dryRun
} else if runActionsEnabled {
    actionExecutionMode = .runActions
} else {
    actionExecutionMode = .disabled
}

func printEvent(
    _ event: NotificationEvent,
    output: WatchOutput,
    redactionPolicy: RedactionPolicy
) {
    let outputEvent = redactionPolicy.applying(to: event)
    let notification = outputEvent.notification
    let timestamp = ISO8601DateFormatter().string(
        from: outputEvent.timestamp
    )

    switch event.type {
    case .appeared:
        output.routine(
            "\(timestamp) event=appeared app=\(notification.app) " +
                "title=\(notification.title) " +
                "subtitle=\(notification.subtitle) " +
                "body=\(notification.body)"
        )

    case .disappeared:
        output.routine(
            "\(timestamp) event=disappeared app=\(notification.app) " +
                "title=\(notification.title) " +
                "subtitle=\(notification.subtitle)"
        )

    case .disappearedUnobserved:
        output.routine(
            "\(timestamp) event=disappeared_unobserved " +
                "app=\(notification.app) " +
                "title=\(notification.title) " +
                "subtitle=\(notification.subtitle)"
        )
    }
}

func integerOption(_ name: String, default defaultValue: Int) -> Int {
    guard let index = arguments.firstIndex(of: name) else {
        return defaultValue
    }

    let valueIndex = arguments.index(after: index)

    guard valueIndex < arguments.endIndex else {
        fputs("Missing value for \(name).\n", stderr)
        exit(2)
    }

    let rawValue = arguments[valueIndex]

    guard let value = Int(rawValue), value > 0 else {
        fputs(
            "Invalid value for \(name): \(rawValue). " +
                "Expected a positive integer.\n",
            stderr
        )
        exit(2)
    }

    return value
}

func stringOption(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name) else {
        return nil
    }

    let valueIndex = arguments.index(after: index)

    guard valueIndex < arguments.endIndex else {
        fputs("Missing value for \(name).\n", stderr)
        exit(2)
    }

    let value = String(arguments[valueIndex])

    guard !value.hasPrefix("--") else {
        fputs("Missing value for \(name).\n", stderr)
        exit(2)
    }

    return value
}

func optionalStringOption(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name) else {
        return nil
    }

    let valueIndex = arguments.index(after: index)

    guard valueIndex < arguments.endIndex else {
        return nil
    }

    let value = arguments[valueIndex]

    guard !value.hasPrefix("-") else {
        return nil
    }

    return value
}

let redactionPolicy: RedactionPolicy

if command == "watch", arguments.contains("--redact") {
    do {
        redactionPolicy = try RedactionPolicy.parse(
            optionalStringOption("--redact")
        )
    } catch {
        fputs(
            "Redaction option error: \(error.localizedDescription)\n",
            stderr
        )
        exit(2)
    }
} else {
    redactionPolicy = .disabled
}

let startupConfiguration = CLIStartupConfiguration(
    runtimePaths: runtimePaths,
    configURL: automationConfigURL(),
    loggingEnabled: loggingEnabled,
    redactionPolicy: redactionPolicy,
    actionExecutionMode: actionExecutionMode,
    scanInterval: 1.0,
    dismissalVerificationDelay: shutUpMacVerificationDelay,
    quietEnabled: quietEnabled,
    debugEnabled: debugEnabled
)

let watchOutput = WatchOutput(
    isQuiet: startupConfiguration.quietEnabled
)

func printHistoryRecord(_ record: NotificationEventRecord) {
    let event = record.event
    let notification = event.notification
    let timestamp = ISO8601DateFormatter().string(from: event.timestamp)

    print("\(record.id)\t\(timestamp)\t\(event.type.rawValue)\t\(notification.app)\t\(notification.title)")
}

func printActionHistoryRecord(_ record: ActionRunRecord) {
    let createdAt = ISO8601DateFormatter().string(from: record.createdAt)

    let exitCodeText: String
    if let exitCode = record.exitCode {
        exitCodeText = String(exitCode)
    } else {
        exitCodeText = "-"
    }

    let verificationText = record.verificationStatus?.rawValue ?? "-"

    print(
        "\(record.id)\t\(createdAt)\t\(record.status.rawValue)" +
            "\texit=\(exitCodeText)" +
            "\tverification=\(verificationText)" +
            "\t\(record.ruleName)" +
            "\t\(record.message)"
    )
}

func matchCriteriaSummary(_ criteria: NotificationMatchCriteria) -> String {
    var parts: [String] = []

    if let eventTypes = criteria.eventTypes {
        let values = eventTypes.map { $0.rawValue }.joined(separator: ",")
        parts.append("eventTypes=[\(values)]")
    }

    if let appEquals = criteria.appEquals {
        parts.append("appEquals=\"\(appEquals)\"")
    }

    if let appContains = criteria.appContains {
        parts.append("appContains=\"\(appContains)\"")
    }

    if let titleContains = criteria.titleContains {
        parts.append("titleContains=\"\(titleContains)\"")
    }

    if let subtitleContains = criteria.subtitleContains {
        parts.append("subtitleContains=\"\(subtitleContains)\"")
    }

    if let bodyContains = criteria.bodyContains {
        parts.append("bodyContains=\"\(bodyContains)\"")
    }

    if let anyTextContains = criteria.anyTextContains {
        parts.append("anyTextContains=\"\(anyTextContains)\"")
    }

    if criteria.caseSensitive {
        parts.append("caseSensitive=true")
    }

    if parts.isEmpty {
        return "all"
    }

    return parts.joined(separator: " ")
}

func printRule(_ rule: NotificationRule) {
    let enabledText = rule.enabled ? "yes" : "no"
    let criteriaText = matchCriteriaSummary(rule.criteria)
    let actionText = rule.actions.map { $0.summary }.joined(separator: "; ")

    print("\(enabledText)\t\(rule.name)\t\(criteriaText)\t\(actionText)")
}

func loadAutomationEngine() throws -> AutomationEngine {
    let configURL = startupConfiguration.configURL

    if FileManager.default.fileExists(atPath: configURL.path) {
        diagnosticHandler?("Loading automation config: \(configURL.path)")

        let config = try AutomationConfig.load(from: configURL)
        let rules = try config.notificationRules()

        diagnosticHandler?("Loaded automation rules: \(rules.count)")

        return AutomationEngine(rules: rules)
    }

    diagnosticHandler?("No automation config found at \(configURL.path); using built-in probe rules")

    return AutomationEngine.builtInProbe()
}

func validateAutomationConfig() throws {
    let configURL = startupConfiguration.configURL

    if !FileManager.default.fileExists(atPath: configURL.path) {
        print("""
        No config found at:
          \(configURL.path)

        Using built-in probe rules.
        """)
        return
    }

    let config = try AutomationConfig.load(from: configURL)
    let rules = try config.notificationRules()

    print("""
    Config OK.
    Path: \(configURL.path)
    Rules: \(rules.count)
    """)
}

func printConfigErrorAndExit(_ error: Error) -> Never {
    if let error = error as? AutomationConfigError {
        fputs("Config error:\n  \(error.description)\n", stderr)
    } else {
        fputs("Config error:\n  \(error.localizedDescription)\n", stderr)
    }

    fputs("\nRun:\n  notilog-cli config-check\n", stderr)
    exit(1)
}

func printRuntimeErrorAndExit(
    _ error: Error
) -> Never {
    let message: String

    if let notilogError = error as? NotilogError {
        message =
            notilogError.errorDescription
                ?? String(describing: notilogError)
    } else {
        message = error.localizedDescription
    }

    fputs(
        "Error: \(message)\n",
        stderr
    )

    exit(1)
}

func automationConfigURL() -> URL {
    if let configPath = stringOption("--config") {
        let expandedPath = (configPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath)
    }

    return runtimePaths.config
}

func printAutomationStartupStatus(
    dryRunEnabled: Bool,
    runEnabled: Bool,
    engine: AutomationEngine,
    output: WatchOutput
) {
    let configURL = startupConfiguration.configURL
    let ruleCount = engine.configuredRules.count

    if dryRunEnabled {
        output.routine("Automation: DRY RUN")
        output.routine("Config: \(configURL.path)")
        output.routine("Rules: \(ruleCount)")
    } else if runEnabled {
        output.routine("Automation: ENABLED")
        output.routine("Config: \(configURL.path)")
        output.routine("Rules: \(ruleCount)")
    } else {
        output.routine("Automation: DISABLED")
        output.routine(
            "Actions will not execute unless --run-actions is specified."
        )
    }
}

func printActionResult(
    _ result: ActionRunResult,
    mode: AutomationExecutionMode,
    output: WatchOutput,
    redactionPolicy: RedactionPolicy
) {
    let notification = result.event.notification
    let outputNotification = redactionPolicy.applying(
        to: notification
    )

    let prefix = mode == .dryRun
        ? "[dry-run]"
        : "[action]"

    let outputMessage: String

    if redactionPolicy.isEnabled {
        if let exitCode = result.exitCode {
            outputMessage =
                "status: \(result.status.rawValue), exit code: \(exitCode)"
        } else {
            outputMessage = "status: \(result.status.rawValue)"
        }
    } else {
        outputMessage = result.message
    }

    output.routineError("""
    \(prefix) matched rule: \(result.ruleName)
      \(outputMessage)
      app: \(outputNotification.app)
      title: \(outputNotification.title)
      subrole: \(outputNotification.subrole)
      axIdentifier: \(outputNotification.axIdentifier)
      key: \(outputNotification.key)

    """)

    if !result.stdout.isEmpty {
        if redactionPolicy.isEnabled {
            output.routineError(
                "  stdout: [SUPPRESSED BY REDACTION]\n"
            )
        } else {
            output.routineError(
                "  stdout: \(result.stdout)\n"
            )
        }
    }

    if !result.stderr.isEmpty {
        if redactionPolicy.isEnabled {
            output.routineError(
                "  stderr: [SUPPRESSED BY REDACTION]\n"
            )
        } else {
            output.routineError(
                "  stderr: \(result.stderr)\n"
            )
        }
    }
}

func printCompletedActionVerifications(
    _ completedVerifications: [CompletedActionVerification],
    output: WatchOutput
) {
    for verification in completedVerifications {
        let actionRunDescription =
            verification.actionRunID.map { String($0) } ?? "not logged"

        output.routineError("""
        [action verification] \(verification.status.rawValue)
          action run id: \(actionRunDescription)
          key: \(verification.notificationKey)

        """)
    }
}

switch command {
case "permissions":
    if Accessibility.isTrusted {
        print("Accessibility: OK")
        exit(0)
    }

    if arguments.contains("--prompt") {
        let trusted = Accessibility.promptForAccess()

        if trusted {
            print("Accessibility: OK")
            exit(0)
        } else {
            print("Accessibility: Not authorized")
            print("Grant access in System Settings → Privacy & Security → Accessibility")
            exit(1)
        }
    }

    print("Accessibility: Not authorized")
    print("Run: notilog-cli permissions --prompt")
    exit(1)

case "watch":
    guard Accessibility.isTrusted else {
        print("""
        Accessibility permission is required.

        Run:
            notilog-cli permissions --prompt

        or grant access in:

            System Settings → Privacy & Security → Accessibility
        """)
        exit(1)
    }

    try startupConfiguration.runtimePaths.ensureDirectoriesExist()

    let monitoringProcessLock: MonitoringProcessLock

    do {
        monitoringProcessLock =
            try MonitoringProcessLock(
                lockFileURL:
                startupConfiguration.runtimePaths.monitorLock
            )

    } catch {
        printRuntimeErrorAndExit(error)
    }
    let scanner = NotificationScanner(
        diagnosticHandler: diagnosticHandler
    )

    let store: NotificationStore?

    do {
        if startupConfiguration.loggingEnabled {
            store = try NotificationStore(
                path:
                startupConfiguration.runtimePaths
                    .database.path
            )
        } else {
            store = nil
        }
    } catch {
        printRuntimeErrorAndExit(error)
    }

    let automationEngine: AutomationEngine

    do {
        automationEngine = try loadAutomationEngine()
    } catch {
        printConfigErrorAndExit(error)
    }

    let automationProcessor = NotificationAutomationProcessor(
        engine: automationEngine
    )

    let automationExecutionMode: AutomationExecutionMode

    switch startupConfiguration.actionExecutionMode {
    case .disabled:
        automationExecutionMode = .disabled

    case .dryRun:
        automationExecutionMode = .dryRun

    case .runActions:
        automationExecutionMode = .runActions
    }

    watchOutput.routine("Watching notifications...")
    printAutomationStartupStatus(
        dryRunEnabled: startupConfiguration.actionExecutionMode.dryRunEnabled,
        runEnabled: startupConfiguration.actionExecutionMode.runActionsEnabled,
        engine: automationEngine,
        output: watchOutput
    )

    if startupConfiguration.loggingEnabled {
        watchOutput.routine("Database logging: ENABLED")
    } else {
        watchOutput.routine(
            "Database logging: DISABLED (--no-logging privacy mode)"
        )
    }

    if startupConfiguration.redactionPolicy.isEnabled {
        let redactedFields =
            startupConfiguration.redactionPolicy.fieldNames.joined(
                separator: ", "
            )

        watchOutput.routine(
            "Redaction: ENABLED (\(redactedFields))"
        )
    } else {
        watchOutput.routine("Redaction: DISABLED")
    }

    watchOutput.routine("Press Ctrl-C to stop.")

    let session = ObservationSession()
    let previouslyActive: [VisibleNotification]

    if let store {
        diagnosticHandler?("Database path: \(startupConfiguration.runtimePaths.database.path)")

        try store.startSession(session)
        diagnosticHandler?("Started session: \(session.id)")

        previouslyActive = try store.loadActiveNotifications()
        diagnosticHandler?("Previously active notifications: \(previouslyActive.count)")
    } else {
        previouslyActive = []
        diagnosticHandler?(
            "Database logging disabled; no session or previous state loaded"
        )
    }

    let cycleProcessor = MonitoringCycleProcessor(
        previouslyActive: previouslyActive
    )

    let completedVerificationCoordinator =
        CompletedActionVerificationCoordinator(
            store: store
        )

    let actionResultCoordinator = ActionResultCoordinator(
        store: store,
        session: session,
        redactionPolicy: startupConfiguration.redactionPolicy,
        cycleProcessor: cycleProcessor,
        dismissalVerificationDelay:
        startupConfiguration.dismissalVerificationDelay
    )

    let eventPersistenceCoordinator =
        NotificationEventPersistenceCoordinator(
            store: store,
            session: session,
            redactionPolicy: startupConfiguration.redactionPolicy
        )

    let notificationEventCoordinator =
        NotificationEventCoordinator(
            persistenceCoordinator: eventPersistenceCoordinator,
            automationProcessor: automationProcessor,
            actionResultCoordinator: actionResultCoordinator
        )

    let monitor = NotificationMonitor(
        cycleProcessor: cycleProcessor,
        completedVerificationCoordinator:
        completedVerificationCoordinator,
        eventCoordinator: notificationEventCoordinator,
        automationMode: automationExecutionMode
    )

    var didReportPreviousStateRecovery = false

    try withExtendedLifetime(monitoringProcessLock) {
        while true {
            let scanTimestamp = Date()
            let notifications = scanner.scan()

            _ = try monitor.processScan(
                notifications: notifications,
                at: scanTimestamp,
                actionTimestampProvider: {
                    Date()
                },
                afterCompletedActionVerifications: {
                    completedVerifications in
                    printCompletedActionVerifications(
                        completedVerifications,
                        output: watchOutput
                    )
                },
                beforeAutomation: { event in
                    printEvent(
                        event,
                        output: watchOutput,
                        redactionPolicy:
                        startupConfiguration.redactionPolicy
                    )
                },
                beforeActionResultCoordination: { result in
                    printActionResult(
                        result,
                        mode: automationExecutionMode,
                        output: watchOutput,
                        redactionPolicy:
                        startupConfiguration.redactionPolicy
                    )
                },
                afterRecoveredEvents: { recoveredEvents in
                    if !didReportPreviousStateRecovery {
                        diagnosticHandler?(
                            "Recovered unobserved disappearances: \(recoveredEvents.count)"
                        )

                        didReportPreviousStateRecovery = true
                    }
                }
            )

            Thread.sleep(
                forTimeInterval: startupConfiguration.scanInterval
            )
        }
    }

case "history":
    let limit = integerOption("--limit", default: 20)

    let records: [NotificationEventRecord]

    do {
        let store = try NotificationStore(
            path:
            startupConfiguration.runtimePaths
                .database.path,
            accessMode: .readOnly
        )

        diagnosticHandler?(
            "Database path: " +
                startupConfiguration.runtimePaths
                .database.path
        )
        diagnosticHandler?(
            "History limit: \(limit)"
        )

        records = try store.recentEvents(
            limit: limit
        )
    } catch {
        printRuntimeErrorAndExit(error)
    }

    if records.isEmpty {
        print("No notification events found.")
        exit(0)
    }

    for record in records {
        printHistoryRecord(record)
    }

case "action-history":
    let limit = integerOption("--limit", default: 20)

    let records: [ActionRunRecord]

    do {
        let store = try NotificationStore(
            path:
            startupConfiguration.runtimePaths
                .database.path,
            accessMode: .readOnly
        )

        diagnosticHandler?(
            "Database path: " +
                startupConfiguration.runtimePaths
                .database.path
        )

        diagnosticHandler?(
            "Action history limit: \(limit)"
        )

        records = try store.recentActionRuns(
            limit: limit
        )
    } catch {
        printRuntimeErrorAndExit(error)
    }

    if records.isEmpty {
        print("No action runs found.")
        exit(0)
    }

    for record in records {
        printActionHistoryRecord(record)
    }

case "rules":
    try startupConfiguration.runtimePaths.ensureDirectoriesExist()

    let engine = try loadAutomationEngine()
    let rules = engine.configuredRules

    if rules.isEmpty {
        print("No rules configured.")
        exit(0)
    }

    print("enabled\tname\tmatch\tactions")

    for rule in rules {
        printRule(rule)
    }

case "config-check":
    try startupConfiguration.runtimePaths.ensureDirectoriesExist()

    do {
        try validateAutomationConfig()
    } catch let error as AutomationConfigError {
        fputs("Config error:\n  \(error.description)\n", stderr)
        exit(1)
    } catch {
        fputs("Config error:\n  \(error.localizedDescription)\n", stderr)
        exit(1)
    }

case "help", "--help", "-h":
    print("""
    notilog-cli

    Usage:
      notilog-cli permissions
      notilog-cli permissions --prompt
      notilog-cli history [--limit N]
      notilog-cli watch [--quiet] [--debug] [--no-logging] [--redact [FIELDS]][--dry-run-actions] [--run-actions] [--config PATH]
      notilog-cli action-history [--limit N]
      notilog-cli rules [--config PATH]
      notilog-cli config-check [--config PATH]
      notilog-cli --version

    Commands:
      permissions       Check Accessibility permission
      watch             Watch visible notifications
      history           Show recent notification events
      action-history    Show recent automation action results
      rules             Show configured automation rules
      config-check      Validate automation config

    Options:
      --quiet           Suppress routine watch output
      --debug           Write diagnostic output to stderr
      --no-logging      Scan and run actions without writing to the database
      --redact [FIELDS] Redact notification fields in output and database records
      --dry-run-actions Print matched automation actions without running them
      --run-actions     Run matched automation actions
      --limit N         Limit history results
      -v, --version     Show the version
      --config PATH     Use a specific automation config file
    """)

default:
    print("Unknown command: \(command)")
    exit(2)
}
