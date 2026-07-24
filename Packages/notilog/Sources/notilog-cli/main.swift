import Foundation
import NotilogCore

let arguments = Array(CommandLine.arguments.dropFirst())

let quietEnabled = arguments.contains("--quiet")

Debug.enabled = arguments.contains("--debug") && !quietEnabled
Debug.log("Debug logging enabled")
if arguments.contains("-v") || arguments.contains("--version") {
    print(notilogVersion)
    exit(0)
}

let command = arguments.first { !$0.hasPrefix("-") } ?? "help"

let dryRunActionsEnabled = arguments.contains("--dry-run-actions")
let runActionsEnabled = arguments.contains("--run-actions")
let loggingEnabled = !arguments.contains("--no-logging")

let watchOutput = WatchOutput(isQuiet: quietEnabled)

struct PendingActionVerification {
    let actionRunID: Int64?
    let notificationKey: String
    let verifyAfter: Date
}

let shutUpMacVerificationDelay: TimeInterval = 2.0

if dryRunActionsEnabled && runActionsEnabled {
    fputs("Use either --dry-run-actions or --run-actions, not both.\n", stderr)
    exit(2)
}

func printEvent(
    _ event: NotificationEvent,
    output: WatchOutput,
    redactionPolicy: RedactionPolicy
) {
    let outputEvent = redactionPolicy.applying(to:event)
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
        return defaultValue
    }

    return Int(arguments[valueIndex]) ?? defaultValue
}

func stringOption(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name) else {
        return nil
    }

    let valueIndex = arguments.index(after: index)

    guard valueIndex < arguments.endIndex else {
        return nil
    }

    return arguments[valueIndex]
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

if command == "watch" && arguments.contains("--redact") {
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
    let configURL = automationConfigURL()

    if FileManager.default.fileExists(atPath: configURL.path) {
        Debug.log("Loading automation config: \(configURL.path)")

        let config = try AutomationConfig.load(from: configURL)
        let rules = try config.notificationRules()

        Debug.log("Loaded automation rules: \(rules.count)")

        return AutomationEngine(rules: rules)
    }

    Debug.log("No automation config found at \(configURL.path); using built-in probe rules")

    return AutomationEngine.builtInProbe()
}

func validateAutomationConfig() throws {
    let configURL = automationConfigURL()

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

func automationConfigURL() -> URL {
    if let configPath = stringOption("--config") {
        let expandedPath = (configPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath)
    }

    return Paths.config
}

func printAutomationStartupStatus(
    dryRunEnabled: Bool,
    runEnabled: Bool,
    engine: AutomationEngine,
    output: WatchOutput
) {
    let configURL = automationConfigURL()
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
func runAutomationIfNeeded(
    for event: NotificationEvent,
    dryRunEnabled: Bool,
    runEnabled: Bool,
    engine: AutomationEngine,
    store: NotificationStore?,
    session: ObservationSession,
    output: WatchOutput,
    redactionPolicy: RedactionPolicy
) throws -> [PendingActionVerification]{
    guard dryRunEnabled || runEnabled else {
        return []
    }

    let matches = engine.evaluate(event)

    let runner = ActionRunner()
    var pendingVerifications: [PendingActionVerification] = []

    for match in matches {
        let result = dryRunEnabled
            ? runner.runDryRun(match)
            : runner.run(match)

        let notification = result.event.notification
        let outputNotification = redactionPolicy.applying(
            to: notification
        )
        
        let prefix = dryRunEnabled ? "[dry-run]" : "[action]"
        
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

        let actionRunID: Int64?

        if let store {
            let storedResult = redactionPolicy.applying(
                to: result
            )
        
            actionRunID = try store.insert(
                storedResult,
                session: session
            )
        } else {
            actionRunID = nil
        }

        if result.verificationStatus == .pending {
            pendingVerifications.append(
                PendingActionVerification(
                    actionRunID: actionRunID,
                    notificationKey: notification.key,
                    verifyAfter: Date().addingTimeInterval(
                        shutUpMacVerificationDelay
                    )
                )
            )
        }
    }

    return pendingVerifications
}

func processDueActionVerifications(
    _ pendingVerifications: inout [PendingActionVerification],
    visibleNotifications: [VisibleNotification],
    now: Date,
    store: NotificationStore?,
    output: WatchOutput
) throws {
    var remainingVerifications: [PendingActionVerification] = []

    for verification in pendingVerifications {
        guard verification.verifyAfter <= now else {
            remainingVerifications.append(verification)
            continue
        }

        let status = ActionVerificationEvaluator.evaluate(
            notificationKey: verification.notificationKey,
            visibleNotifications: visibleNotifications
        )

                if let store, let actionRunID = verification.actionRunID {
            try store.updateActionVerificationStatus(
                status,
                forActionRunID: actionRunID
            )
        }

        let actionRunDescription =
            verification.actionRunID.map { String($0) } ?? "not logged"

        output.routineError("""
        [action verification] \(status.rawValue)
          action run id: \(actionRunDescription)
          key: \(verification.notificationKey)
        
        """)
    }

    pendingVerifications = remainingVerifications
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

    try Paths.ensureRuntimeDirectoriesExist()

    let scanner = NotificationScanner()
    let tracker = NotificationEventTracker()

    let store: NotificationStore?

    if loggingEnabled {
        store = try NotificationStore(path: Paths.database.path)
    } else {
        store = nil
    }

    let automationEngine: AutomationEngine

    do {
        automationEngine = try loadAutomationEngine()
    } catch {
        printConfigErrorAndExit(error)
    }

    watchOutput.routine("Watching notifications...")
    printAutomationStartupStatus(
        dryRunEnabled: dryRunActionsEnabled,
        runEnabled: runActionsEnabled,
        engine: automationEngine,
        output: watchOutput
    )
    
    if loggingEnabled {
        watchOutput.routine("Database logging: ENABLED")
    } else {
        watchOutput.routine(
            "Database logging: DISABLED (--no-logging privacy mode)"
        )
    }
    
    if redactionPolicy.isEnabled {
        let redactedFields = redactionPolicy.fieldNames.joined(
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
        Debug.log("Database path: \(Paths.database.path)")
    
        try store.startSession(session)
        Debug.log("Started session: \(session.id)")
    
        previouslyActive = try store.loadActiveNotifications()
        Debug.log("Previously active notifications: \(previouslyActive.count)")
    } else {
        previouslyActive = []
        Debug.log(
            "Database logging disabled; no session or previous state loaded"
        )
    }

    var didRecoverPreviousState = false
    var pendingActionVerifications: [PendingActionVerification] = []

    while true {
        let notifications = scanner.scan()
        let scanTimestamp = Date()

        try processDueActionVerifications(
            &pendingActionVerifications,
            visibleNotifications: notifications,
            now: scanTimestamp,
            store: store,
            output: watchOutput
        )

        let snapshot = NotificationSnapshot(
            timestamp: scanTimestamp,
            notifications: notifications
        )

        if !didRecoverPreviousState {
            let currentKeys = Set(notifications.map { $0.key })

            let recoveredEvents = previouslyActive
                .filter { !currentKeys.contains($0.key) }
                .map {
                    NotificationEvent(
                        type: .disappearedUnobserved,
                        notification: $0,
                        timestamp: snapshot.timestamp
                    )
                }

            if let store {
                let storedEvents = recoveredEvents.map {
                    redactionPolicy.applying(to: $0)
                }

                try store.insert(storedEvents, session: session)
            }

            for event in recoveredEvents {
                printEvent(
                    event,
                    output: watchOutput,
                    redactionPolicy: redactionPolicy
                )

                let newVerifications = try runAutomationIfNeeded(
                    for: event,
                    dryRunEnabled: dryRunActionsEnabled,
                    runEnabled: runActionsEnabled,
                    engine: automationEngine,
                    store: store,
                    session: session,
                    output: watchOutput,
                    redactionPolicy: redactionPolicy
                )

                pendingActionVerifications.append(
                    contentsOf: newVerifications
                )

            }

            Debug.log("Recovered unobserved disappearances: \(recoveredEvents.count)")

            didRecoverPreviousState = true
        }

        let events = tracker.update(with: snapshot)

        if let store {
            let storedEvents = events.map {
                redactionPolicy.applying(to: $0)
            }
        
            try store.insert(storedEvents, session: session)
        }
        
        for event in events {
            printEvent(
                event,
                output: watchOutput,
                redactionPolicy: redactionPolicy
            )

            let newVerifications = try runAutomationIfNeeded(
                for: event,
                dryRunEnabled: dryRunActionsEnabled,
                runEnabled: runActionsEnabled,
                engine: automationEngine,
                store: store,
                session: session,
                output: watchOutput,
                redactionPolicy: redactionPolicy
            )

            pendingActionVerifications.append(
                contentsOf: newVerifications
            )

        }

        Thread.sleep(forTimeInterval: 1.0)
    }

case "history":
    let limit = integerOption("--limit", default: 20)

    try Paths.ensureRuntimeDirectoriesExist()

    let store = try NotificationStore(path: Paths.database.path)

    Debug.log("Database path: \(Paths.database.path)")
    Debug.log("History limit: \(limit)")

    let records = try store.recentEvents(limit: limit)

    if records.isEmpty {
        print("No notification events found.")
        exit(0)
    }

    for record in records {
        printHistoryRecord(record)
    }

case "action-history":
    let limit = integerOption("--limit", default: 20)

    try Paths.ensureRuntimeDirectoriesExist()

    let store = try NotificationStore(path: Paths.database.path)

    Debug.log("Database path: \(Paths.database.path)")
    Debug.log("Action history limit: \(limit)")

    let records = try store.recentActionRuns(limit: limit)

    if records.isEmpty {
        print("No action runs found.")
        exit(0)
    }

    for record in records {
        printActionHistoryRecord(record)
    }

case "rules":
    try Paths.ensureRuntimeDirectoriesExist()

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
    try Paths.ensureRuntimeDirectoriesExist()

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
