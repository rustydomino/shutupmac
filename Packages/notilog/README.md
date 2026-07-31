# notilog

**notilog** is a macOS notification observation, logging, privacy, and automation framework built on the Accessibility (AX) API.

Rather than depending on Apple's undocumented notification database, Notilog observes notifications as they appear in the Notification Center user interface. It can record notification lifecycle events, evaluate rules, execute actions, verify ShutUpMac dismissals, and operate with configurable logging, console, and redaction policies.

The project consists of a reusable Swift library, `NotilogCore`, and a CLI host, `notilog-cli`. `NotificationMonitor` exposes one complete, nonblocking monitoring cycle. The ShutUpMac app now embeds that facade directly, reusing the same event, automation, persistence, verification, and redaction behavior without launching or duplicating the CLI.

## Current Features

- Observe visible macOS notifications through Accessibility.
- Extract:
  - Notification key
  - AX subrole
  - AX identifier
  - Source application
  - Title
  - Subtitle
  - Body
- Detect `appeared`, `disappeared`, and recovered `disappeared_unobserved` events.
- Debounce short AX disappearances before emitting lifecycle events.
- Track active notifications and reconcile state after interrupted watch sessions.
- Persist notification history, active state, watch sessions, and action results to SQLite.
- Inspect notification and action history from the CLI.
- Define multiple JSON automation rules and multiple actions per rule.
- Match event type, app, title, subtitle, body, or combined notification text.
- Expand event and notification template variables in action arguments.
- Preview actions with `--dry-run-actions`.
- Run direct `exec` actions without invoking a shell.
- Capture action status, exit code, stdout, and stderr.
- Use the dedicated `shutupmac_dismiss` action.
- Track delayed ShutUpMac outcomes as `probably_succeeded` or `definitely_failed`.
- Run with no database writes using `--no-logging`.
- Suppress routine watch output using `--quiet`.
- Redact selected notification fields in Notilog-owned console and database output using `--redact`.
- Fall back to a safe built-in probe rule when no config exists.
- Use host-configurable runtime paths and diagnostic callbacks.
- Process one explicit notification scan through the reusable `NotificationMonitor` facade.
- Keep lifecycle, timestamps, and presentation under host control.

## Requirements

- macOS 13 or later
- Swift 6.3 toolchain
- Accessibility permission for the terminal or application running Notilog
- ShutUpMac installed only when using the `shutupmac_dismiss` action

For command-line development, Accessibility permission normally belongs to the launching application, such as Terminal, Ghostty, iTerm2, or Xcode.

## Building and Testing

From the ShutUpMac repository root:

```zsh
swift build --package-path Packages/notilog
```

Show the SwiftPM binary directory:

```zsh
swift build \
  --package-path Packages/notilog \
  --show-bin-path
```

Run the test suite:

```zsh
swift test --package-path Packages/notilog
```

During development, commands can be run through SwiftPM:

```zsh
swift run \
  --package-path Packages/notilog \
  notilog-cli help
```

The remaining examples use `notilog-cli` directly and assume the built executable is available on `PATH`. From the repository root, the debug binary is normally available at:

```text
Packages/notilog/.build/debug/notilog-cli
```

## Runtime Files

Runtime paths are host-configurable through `NotilogRuntimePaths`. The CLI preserves the legacy default directory:

```text
~/Library/Application Support/notilog/
```

Current CLI paths:

```text
notilog.sqlite   SQLite database
config.json      Optional automation configuration
logs/            Reserved runtime log directory
```

An embedding host may supply a different application-support root or fully explicit config, database, and logs URLs.

## ShutUpMac App Host

The ShutUpMac app currently uses the legacy Notilog runtime directory and owns the watcher lifecycle with a timer-driven host around `NotificationMonitor`. On launch it loads recent notification appearance records into the Activity window and then appends live monitoring results. The app also hosts the Rules window and injects an in-process dismissal handler so `shutupmac_dismiss` actions do not launch the external helper.

ShutUpMac Settings provides live controls for:

- Enabling or disabling notification logging. When disabled, scanning, rules, actions, and verification continue, but new SQLite records and Activity rows are suppressed.
- Redacting title, subtitle, and body. Selected nonempty fields become `[REDACTED]` in subsequent Activity rows and database writes. The application name remains visible in the GUI.

The GUI controls intentionally expose a smaller redaction surface than the CLI. `notilog-cli --redact` continues to support `app` and the reserved `attachments` field in addition to title, subtitle, and body.

## Quick Start

Check Accessibility permission:

```zsh
notilog-cli permissions
```

Request the system permission prompt:

```zsh
notilog-cli permissions --prompt
```

Start watching notifications:

```zsh
notilog-cli watch
```

Stop the foreground watch process with `Ctrl-C`.

## Commands

### Permissions

```zsh
notilog-cli permissions
notilog-cli permissions --prompt
```

### Watch

Basic watch:

```zsh
notilog-cli watch
```

Enable diagnostic output:

```zsh
notilog-cli watch --debug
```

Preview matched actions without executing them:

```zsh
notilog-cli watch --dry-run-actions
```

Execute matched actions:

```zsh
notilog-cli watch --run-actions
```

Use a specific config file:

```zsh
notilog-cli watch --run-actions --config ./Examples/config.example.json
```

`--dry-run-actions` and `--run-actions` are mutually exclusive.

### Notification History

```zsh
notilog-cli history
notilog-cli history --limit 50
```

### Action History

```zsh
notilog-cli action-history
notilog-cli action-history --limit 50
```

### Rules

```zsh
notilog-cli rules
notilog-cli rules --config ./Examples/config.example.json
```

### Config Validation

```zsh
notilog-cli config-check
notilog-cli config-check --config ./Examples/config.example.json
```

### Version and Help

```zsh
notilog-cli --version
notilog-cli -v
notilog-cli help
```

## Privacy and Output Modes

The following watch options control different parts of the pipeline and can be combined.

| Option | Controls | Scanning and actions | SQLite writes | Routine console output |
|---|---|---:|---:|---:|
| none | Normal operation | Yes | Yes | Yes |
| `--no-logging` | Persistence | Yes | No | Yes |
| `--quiet` | Routine watch output | Yes | Yes | No |
| `--redact` | Stored/displayed content | Yes | Yes, redacted | Yes, redacted |

### No-Logging Mode

```zsh
notilog-cli watch --no-logging --run-actions
```

`--no-logging` does not open or write the SQLite database. Notilog still:

- Scans notifications.
- Emits events in memory.
- Matches rules.
- Executes enabled actions.
- Tracks pending ShutUpMac verification in memory.

Because there is no database, the session does not recover previously active notification state and action verification results are not persisted.

### Quiet Mode

```zsh
notilog-cli watch --quiet --run-actions
```

`--quiet` suppresses routine watch output, including:

- Startup status.
- Notification event lines.
- Rule and action reports.
- Captured child stdout and stderr.
- Delayed ShutUpMac verification reports.
- Debug messages, even when `--debug` is also present.

Fatal startup and configuration errors may still be written to standard error. Quiet mode does not disable database writes or action execution.

A silent, non-persistent automation session can combine both policies:

```zsh
notilog-cli watch --no-logging --quiet --run-actions
```

### Redaction Mode

Bare `--redact` uses the default field set:

```zsh
notilog-cli watch --redact
```

Equivalent explicit alias:

```zsh
notilog-cli watch --redact default
```

The default set is:

```text
title, subtitle, body, attachments
```

Redact every supported field, including the application name:

```zsh
notilog-cli watch --redact all
```

Select individual fields with a comma-separated list:

```zsh
notilog-cli watch --redact title,body
notilog-cli watch --redact app,title,subtitle,body
```

Supported field names:

```text
app
title
subtitle
body
attachments
```

The scanner does not currently capture attachment data; `attachments` reserves the privacy policy for future attachment support.

Selected nonempty values become:

```text
[REDACTED]
```

Genuinely empty values remain empty.

Redaction currently protects:

- Notification event console output.
- Immediate action console reports.
- Child stdout/stderr displayed or stored by Notilog.
- `notification_events`.
- `active_notifications`.
- `action_runs`, including expanded action details.

Rules and actions still evaluate the original notification in memory. This means an external `exec` action can receive original content when its configured arguments use templates such as `{{notification.body}}`. The external process is outside Notilog's redaction boundary.

Redaction currently does not hide notification keys, AX identifiers, AX subroles, rule names, user-authored config strings, or rows written before redaction was enabled.

Common privacy combination:

```zsh
notilog-cli watch --redact --quiet --run-actions
```

## Architecture

```text
Notification Center AX tree
          │
          ▼
 NotificationScanner                    host-owned
          │
          ▼
 [VisibleNotification]
          │
          ▼
 NotificationMonitor                    one reusable cycle
          │
    ┌─────┴──────────────────────────────────────────┐
    ▼                                                ▼
MonitoringCycleProcessor                   NotificationEventCoordinator
    │                                                │
    ├─ event recovery/tracking                       ├─ persistence
    └─ due verification evaluation                   ├─ automation
                                                     └─ action coordination
```

The host supplies scans and timestamps, receives typed results through `NotificationMonitor`, and chooses how to render them. `notilog-cli` owns its AX polling loop, sleeping, argument parsing, and terminal output. The ShutUpMac app owns a separate timer-driven lifecycle and Activity presentation. `NotilogCore` owns the reusable event, action, persistence, verification, and redaction coordination shared by both hosts.

The original event is used for rule matching and configured actions. Redacted copies are created for Notilog-owned output and persistence.

See [`architecture.md`](architecture.md) for the processor/coordinator breakdown and data-flow details.

### Embedding `NotilogCore`

A host assembles the scanner and runtime dependencies, then repeatedly calls the monitor with one scan:

```swift
let result = try monitor.processScan(
    notifications: scanner.scan(),
    at: Date(),
    actionTimestampProvider: { Date() },
    afterCompletedActionVerifications: renderVerifications,
    beforeAutomation: renderEvent,
    beforeActionResultCoordination: renderAction,
    afterRecoveredEvents: reportRecovery
)
```

The monitor does not call `Date()`, scan Accessibility, sleep, or create an infinite task. Those lifecycle choices remain with the host.

## Automation Configuration

The default automation config path is:

```text
~/Library/Application Support/notilog/config.json
```

A config contains a `rules` array. Each enabled rule has match criteria and one or more actions.

Example with two rules:

```json
{
  "rules": [
    {
      "id": "7f8fa3fc-df90-4df8-93fd-ff7fe8cb3936",
      "name": "Dismiss Self Service+ Agent notifications",
      "enabled": true,
      "match": {
        "eventTypes": ["appeared"],
        "appEquals": "Self Service+ Agent",
        "caseSensitive": false
      },
      "actions": [
        {
          "type": "shutupmac_dismiss"
        }
      ]
    },
    {
      "id": "acd29f2c-42b5-4779-ae7b-b9bf43a71c53",
      "name": "Record update completion",
      "enabled": true,
      "match": {
        "eventTypes": ["appeared"],
        "appEquals": "Self Service+",
        "bodyContains": "Update complete",
        "caseSensitive": false
      },
      "actions": [
        {
          "type": "dry_run_log",
          "message": "Update completion from {{notification.app}}"
        }
      ]
    }
  ]
}
```

If no config file exists, Notilog uses a built-in appeared-notification probe backed by `/usr/bin/true`. Actions still require `--dry-run-actions` or `--run-actions`.

## Rule Matching

Current match fields:

```json
{
  "eventTypes": ["appeared"],
  "appEquals": "Mail",
  "appContains": "Self Service",
  "titleEquals": "Build complete",
  "titleContains": "Microsoft Teams",
  "subtitleEquals": "Deployment",
  "subtitleContains": "example",
  "bodyEquals": "Update finished.",
  "bodyContains": "update is available",
  "anyTextContains": "search text",
  "caseSensitive": false
}
```

All specified positive criteria must match. Exact title, subtitle, and body matching uses the same `caseSensitive` setting as contains matching.

Rules may also define exceptions:

```json
{
  "exceptions": [
    {
      "field": "title",
      "contains": "Important"
    },
    {
      "field": "body",
      "contains": "do not dismiss"
    }
  ]
}
```

Exception rows are combined with OR. If any exception matches, the rule does not produce actions. Matching is case-insensitive by default; set `caseSensitive` to `true` for exact case behavior across positive criteria and exceptions.

Current event types:

```text
appeared
disappeared
disappeared_unobserved
```

`anyTextContains` searches a combined string containing app, title, subtitle, and body.

## Actions

### `exec`

Runs an executable directly with argument-array semantics:

```json
{
  "type": "exec",
  "command": "/usr/bin/true",
  "arguments": [
    "--notification-key",
    "{{notification.key}}"
  ]
}
```

Rules:

- `command` must be an absolute path.
- `command` is not template-expanded.
- Each argument is template-expanded.
- Notilog does not invoke a shell automatically.
- Exit code, status, stdout, and stderr are captured.

### `dry_run_log`

Expands a message and records what would be logged:

```json
{
  "type": "dry_run_log",
  "message": "Notification from {{notification.app}}: {{notification.title}}"
}
```

Both spellings are accepted in config:

```text
dry_run_log
dryRunLog
```

### `shutupmac_dismiss`

Dismisses the matched notification through ShutUpMac using the notification key:

```json
{
  "type": "shutupmac_dismiss"
}
```

`ActionRunner` accepts an optional host-provided dismissal handler. When supplied, the handler receives the notification AX key and the external command is not launched. The embedded ShutUpMac app uses this path to call `ShutUpMac.dismissVisibleNotificationResult(matching:)` directly.

When no handler is supplied, such as in standalone `notilog-cli` operation, the action falls back to the helper command.

Default helper:

```text
/Applications/ShutUpMac.app/Contents/Helpers/shutupmac-cli
```

Override the helper path when needed:

```json
{
  "type": "shutupmac_dismiss",
  "command": "/absolute/path/to/shutupmac-cli"
}
```

For one notification event, all matching rules remain reported and non-dismiss actions still run in configured order, but only the first `shutupmac_dismiss` action is executed. This prevents duplicate dismissal attempts when multiple rules match the same event.

Verification depends on the execution path:

- The embedded ShutUpMac handler can report an immediate clear result. A confirmed clear is recorded as `probably_succeeded`; an immediate failure is recorded as `definitely_failed`.
- The external-helper fallback normally schedules a delayed AX check:

```text
notification key absent  → probably_succeeded
notification key present → definitely_failed
```

An immediate ShutUpMac response that says the action was performed but no visible progress was observed is treated as `uncertain` with `pending` verification while awaiting the delayed check.

## Template Variables

Action arguments and dry-run messages can use:

```text
{{event.type}}
{{event.timestamp}}
{{notification.key}}
{{notification.subrole}}
{{notification.axIdentifier}}
{{notification.app}}
{{notification.title}}
{{notification.subtitle}}
{{notification.body}}
```

Unknown placeholders are left unchanged to make configuration mistakes easier to inspect.

## Action and Verification Status

Action execution status:

```text
dry_run
succeeded
uncertain
failed
```

Dismissal verification status:

```text
pending
probably_succeeded
definitely_failed
```

The in-process ShutUpMac host may return a terminal verification status immediately. The external-helper path uses `pending` until a later scan checks whether the original AX key remains visible.

## SQLite Storage

Current tables:

```text
notification_events   Historical lifecycle events
active_notifications  Notifications believed to be visible
watch_sessions        Observation session records
action_runs           Action execution and verification results
```

The schema stores notification identity and content fields separately and uses `PRAGMA user_version` for schema versioning.

Example inspection from the repository root:

```zsh
sqlite3 -header -column \
  "$HOME/Library/Application Support/notilog/notilog.sqlite" '
SELECT
    id,
    event_type,
    app,
    title,
    subtitle,
    body
FROM notification_events
ORDER BY id DESC
LIMIT 10;
'
```


## Current Boundaries

- Notification observation depends on the shape and availability of macOS Accessibility data.
- The CLI polls once per second; `NotilogCore` itself has no fixed cadence.
- The reusable monitor processes one supplied scan synchronously.
- Actions execute synchronously and can delay the next host-scheduled scan.
- Attachment data is not currently captured.
- Raw notification keys and AX identifiers are retained even when content redaction is enabled.
- Redaction affects new output and writes; it does not sanitize old database rows.
- External actions may store, transmit, or print data they receive.
- Pending dismissal verification is in memory and is not resumed after process restart.
- macOS may expose multiple notifications from one app as one collapsed AX stack. Dismissing a matching stack can clear older nonmatching notifications in that stack because individual collapsed children are not dependably targetable through the current Accessibility tree.
- The ShutUpMac app and `notilog-cli` are both supported hosts. The app provides Activity, privacy controls, and a deliberately limited Rules editor; the CLI remains the broader diagnostic and advanced-configuration surface.

## License

This project is licensed under the **GNU General Public License v2.0 (GPL-2.0)**. See `LICENSE` for the full license text.
