# Notilog Architecture

## Project Goal

Notilog is a macOS notification observation, logging, and automation engine built around the Accessibility (AX) API.

The project currently provides a Swift package with:

- `NotilogCore`, a reusable library containing scanning, event tracking, persistence, rule matching, action execution, verification, and redaction logic.
- `notilog-cli`, a command-line client that configures and runs the core engine.

The ShutUpMac app is a production GUI host of `NotilogCore`; it reuses the same monitor, rule, action, persistence, verification, retention, and error behavior as the CLI.

The live Accessibility tree is the runtime source of truth. Apple's internal notification database may be useful for research and validation, but it is not a Notilog runtime dependency.

---

## High-Level Runtime Flow

```text
macOS Notification Center AX tree
              │
              ▼
     NotificationScanner                 host-owned
              │
              ▼
    [VisibleNotification]
              │
              ▼
      NotificationMonitor                reusable one-cycle facade
              │
       ┌──────┼───────────────────────────────────────┐
       │      │                                       │
       ▼      ▼                                       ▼
MonitoringCycleProcessor                 NotificationEventCoordinator
       │                                          │
       ├── NotificationEventProcessor             ├── event persistence
       │      ├── startup recovery                 ├── rule evaluation
       │      └── appeared/disappeared tracking    ├── action execution
       │                                          └── action-result persistence
       └── ActionVerificationProcessor
              └── due verification evaluation

CompletedActionVerificationCoordinator
              └── persisted verification-status updates
```

A host supplies one visible-notification scan and an explicit timestamp to `NotificationMonitor.processScan(...)`. The monitor coordinates one complete, nonblocking cycle and returns typed results. It does not scan Accessibility, call `Date()`, print output, sleep, or own an infinite loop.

The original in-memory notification remains available to rule matching and configured actions. Redaction is applied to copies that cross Notilog-owned output and persistence boundaries.

## Design Principles

- Keep reusable behavior inside `NotilogCore`.
- Keep the CLI focused on argument parsing, lifecycle control, and presentation.
- Treat the AX tree as the authoritative live notification state.
- Keep the persistence layer independent of Accessibility APIs.
- Keep rule evaluation independent of storage and console policy.
- Make privacy controls explicit and composable.
- Execute external commands directly without automatically invoking a shell.
- Preserve enough operational metadata to debug automation without requiring notification content.

---

## Package Structure

```text
Package.swift
Sources/
├── NotilogCore/
│   ├── Accessibility and AX helpers
│   ├── Notification scanner and models
│   ├── Event and verification processors
│   ├── Monitoring-cycle and monitor facades
│   ├── Persistence coordinators and read-only/read-write SQLite store
│   ├── Schema versioning, typed errors, and retention configuration
│   ├── Automation config, rules, and matching
│   ├── Template expansion and action execution
│   ├── Runtime paths and diagnostic handler
│   └── Redaction policy
└── notilog-cli/
    ├── Startup configuration and command dispatch
    ├── Host-owned AX scan/sleep loop
    └── Terminal output formatting
Tests/
└── NotilogCoreTests/
```

### Reusable Monitoring Types

The Phase 4 library-first refactor introduced focused, composable types:

| Type | Responsibility |
|---|---|
| `NotificationEventProcessor` | First-scan recovery plus appeared/disappeared event derivation |
| `ActionVerificationProcessor` | In-memory scheduling and evaluation of delayed dismiss checks |
| `MonitoringCycleProcessor` | Combines event derivation and due verification evaluation for one scan |
| `NotificationAutomationProcessor` | Rule evaluation and action execution in disabled, dry-run, or real mode |
| `NotificationEventPersistenceCoordinator` | Redacted, optional persistence of notification events |
| `ActionResultCoordinator` | Redacted action-result persistence and verification scheduling |
| `CompletedActionVerificationCoordinator` | Persistence of completed verification status |
| `NotificationEventCoordinator` | Ordered event persistence, host callbacks, automation, and action-result coordination |
| `NotificationMonitor` | Public facade that coordinates one complete monitoring cycle |

The smaller processors and coordinators remain public so hosts and tests can use the lowest useful abstraction. Most application hosts should begin with `NotificationMonitor`.

## Core Notification Model

### `VisibleNotification`

A normalized notification extracted from the AX tree:

```text
key
subrole
axIdentifier
app
title
subtitle
body
```

The current notification key is composed from the AX subrole and AX identifier:

```text
<subrole>|<axIdentifier>
```

This key is used for lifecycle correlation, active-state tracking, and ShutUpMac dismissal verification.

### `NotificationSnapshot`

Represents one scan of visible notifications at a specific timestamp.

### `NotificationEvent`

Represents a notification lifecycle transition:

```text
appeared
disappeared
disappeared_unobserved
```

`disappeared_unobserved` is generated during startup reconciliation when a notification persisted as active in the previous session but is absent from the first current scan.

---

## Scanner and Event Tracking

### Accessibility and AX Helpers

The Accessibility layer:

- Checks whether the process is trusted for Accessibility access.
- Can request the system permission prompt.
- Wraps AX attribute reads and child traversal.
- Supports AX subtree diagnostics when debug output is enabled.

### `NotificationScanner`

The scanner:

- Locates known Notification Center processes.
- Traverses their AX trees.
- Detects notification alert and alert-stack subroles.
- Extracts app, title, subtitle, body, subrole, and AX identifier.
- Deduplicates candidates by notification key.
- Produces `[VisibleNotification]`.

### `NotificationEventTracker`

The tracker compares successive snapshots and emits lifecycle events.

A notification must be absent for two consecutive scans by default before a `disappeared` event is emitted. This debounce protects against short-lived AX churn.

### `NotificationEventProcessor`

`NotificationEventProcessor` owns a tracker plus first-scan recovery state. Given `[VisibleNotification]` and an explicit timestamp, it returns recovered `disappeared_unobserved` events separately from ordinary current-session events. This preserves the established recovered-before-current processing order.

`MonitoringCycleProcessor` combines this event processing with due dismissal-verification evaluation. The CLI currently supplies one AX scan per second, but the core does not own that cadence.

---

## Persistence

### `NotificationStore`

`NotificationStore` owns SQLite access and has no dependency on AX APIs.

The database is stored at:

```text
~/Library/Application Support/notilog/notilog.sqlite
```

Current tables:

| Table | Purpose |
|---|---|
| `notification_events` | Historical appeared, disappeared, and recovered lifecycle events |
| `active_notifications` | Notifications believed to be currently visible |
| `watch_sessions` | Observation-session identifiers and timestamps |
| `action_runs` | Dry-run and real automation outcomes, including verification state |

The store maintains indexes for common timestamp, event type, application, identifier, session, status, and notification-key queries.

Schema evolution uses SQLite `PRAGMA user_version` plus targeted migrations. The current schema version is 4. Startup behavior is explicit:

- A current schema opens without modification.
- A new empty database is created only by a read-write store.
- A recognized legacy schema is migrated only by a read-write store.
- A read-only caller rejects any schema requiring migration.
- A newer-than-supported or unrecognized schema fails safely.

`NotificationStore` accepts `NotificationStoreAccessMode.readWrite` or `.readOnly`. Read-only mode uses `SQLITE_OPEN_READONLY`, requires the file to exist, skips retention pruning, and rejects every public mutation method with `NotilogError.readOnlyMutation`. Read-only history inspection therefore cannot create, migrate, prune, or write the database.

### Retention Configuration

The GUI and CLI share `RetentionConfiguration` through:

```text
~/Library/Application Support/notilog/retention.json
```

Built-in defaults are 25,000 notification events and 10,000 action runs. Valid ranges are 1,000–100,000 events and 1,000–50,000 action runs. Missing configuration resolves to defaults without creating a file. Saves are atomic, malformed configuration is reported without implicit replacement, and writer startup or the GUI Apply operation enforces the selected limits.

Notification-event and action-run pruning are independent. Historical event pruning preserves active-notification state and removes ended watch sessions only when no retained historical event references them.

### Active-State Recovery

When database logging is enabled, watch startup:

1. Creates a new observation session.
2. Loads the prior `active_notifications` set.
3. Performs the first live scan.
4. Emits `disappeared_unobserved` for prior keys that are no longer visible.
5. Continues normal snapshot comparison.

When CLI `watch --no-logging` is active, the database is not opened, no session is written, and prior active state is not loaded. The ShutUpMac GUI intentionally differs: when logging is disabled and a database already exists, the app may keep a read-only store solely to display existing Activity history. That connection cannot create, migrate, prune, or write. If the database is missing, the GUI does not create it.

Persistence is coordinated by reusable core types rather than the CLI watch loop:

- `NotificationEventPersistenceCoordinator` applies redaction and optionally inserts event batches.
- `ActionResultCoordinator` applies redaction, optionally inserts action results, and schedules delayed verification with the resulting action-run ID.
- `CompletedActionVerificationCoordinator` updates stored action rows when delayed verification completes.

Each coordinator accepts an optional `NotificationStore`, allowing the same monitoring pipeline to operate when persistence is disabled.

---

## Automation

### Configuration

Automation rules are normally loaded from:

```text
~/Library/Application Support/notilog/config.json
```

A different path may be supplied with `--config PATH`.

If no config file exists, Notilog uses a built-in safe probe rule that matches appeared notifications and executes `/usr/bin/true` only when action execution is enabled.

### Rule Evaluation

`AutomationEngine` evaluates each event against enabled rules. All specified criteria must match.

Current criteria:

```text
eventTypes
appEquals
appContains
titleEquals
titleContains
subtitleEquals
subtitleContains
bodyEquals
bodyContains
anyTextContains
caseSensitive
```

Rules may also define title, subtitle, or body exceptions. All positive criteria are combined with AND. Exception rows are combined with OR, and any matching exception suppresses the rule's actions. Exact and contains matching share the rule-level case-sensitivity setting.

One matching rule can produce multiple `AutomationMatch` values when it defines multiple actions.

`NotificationAutomationProcessor` combines rule evaluation with execution-mode selection. It preserves rule-array and action-array order and returns `[ActionRunResult]` without printing or persisting them. All matching rules remain represented in the detailed result, but only the first `shutupmac_dismiss` action for one notification event is executed; non-dismiss actions continue in configured order.

### Template Expansion

`TemplateExpander` resolves event and notification placeholders in action arguments and dry-run messages.

The executable path of an `exec` action is not template-expanded. Argument values are expanded individually.

### Action Execution

`ActionRunner` supports:

- `dry_run_log`
- `exec`
- `shutupmac_dismiss`

External commands are run with `Foundation.Process` and argument-array semantics. Notilog does not automatically invoke a shell.

For `exec` actions:

- The command must use an absolute path.
- The file must be executable.
- Standard output and standard error are captured.
- Exit code and action status are recorded.

Current action statuses:

```text
dry_run
succeeded
uncertain
failed
```

---

## ShutUpMac Integration and Verification

`shutupmac_dismiss` is a dedicated semantic action rather than a generic shell command that happens to invoke ShutUpMac.

`ActionRunner` accepts an optional `NotificationDismissalHandler` dependency:

```text
handler supplied    -> host performs in-process dismissal
no handler supplied -> run shutupmac-cli --dismiss-key <notification-key>
```

The embedded ShutUpMac app injects a closure that converts the raw key to `NotificationAXKey` and calls `ShutUpMac.dismissVisibleNotificationResult(matching:)`. This reuses the existing Accessibility dismissal engine without starting a helper process.

The standalone CLI retains the external fallback. Its default helper path is:

```text
/Applications/ShutUpMac.app/Contents/Helpers/shutupmac-cli
```

A rule may override that fallback path with its `command` field.

macOS can represent multiple notifications from one application as a single collapsed `AXNotificationCenterAlertStack`. The available stack action is Clear All, so dismissing a matching stacked notification can also clear older nonmatching notifications in that stack. This is a current Accessibility-tree limitation rather than a rule-evaluation distinction.

### Delayed Verification

The external-helper fallback schedules a delayed check after an accepted dismissal request. The known ShutUpMac "performed but no visible progress" response is recorded as `uncertain` with `pending` verification.

The verifier compares the original notification key against a later visible-notification set:

```text
key absent  → probably_succeeded
key present → definitely_failed
```

The embedded ShutUpMac handler can instead return a terminal result immediately. A reported clear becomes `succeeded` with `probably_succeeded`; a reported failure becomes `failed` with `definitely_failed`. Absence is still described as probable rather than absolute proof of the cause.

`ActionVerificationProcessor` owns pending verification state and evaluates checks that are due during a later scan. `CompletedActionVerificationCoordinator` optionally updates the corresponding `action_runs.verification_status` row.

Under `--no-logging`, the pending check still exists in memory with a `nil` action-run ID, and the result can still be returned to the host and reported to the console.

---

## Privacy and Output Policies

Notilog currently has three independent watch policies.

### Persistence Policy: `--no-logging`

- Does not open or write the SQLite database.
- Does not persist sessions, notification events, active state, or action runs.
- Continues scanning, rule matching, action execution, and in-memory ShutUpMac verification.

### Console Policy: `--quiet`

- Suppresses routine watch startup, event, action, captured child output, delayed verification, and debug messages.
- Does not disable scanning, actions, or database writes.
- Fatal startup and configuration errors may still be written to standard error.
- Non-watch commands such as `history`, `rules`, and `--version` remain printable.

`WatchOutput` is the CLI-side gateway for routine watch output.

### Content Policy: `--redact`

`RedactionPolicy` supports these fields:

```text
app
title
subtitle
body
attachments
```

Aliases:

```text
default = title, subtitle, body, attachments
all     = app, title, subtitle, body, attachments
```

The current scanner does not capture attachment data; the selector reserves the policy behavior for future attachment support.

Redaction currently applies to:

- Notification event console output.
- Immediate action console output.
- Captured action stdout/stderr shown or stored by Notilog.
- `notification_events` records.
- `active_notifications` records.
- `action_runs` records and resolved action details.

Nonempty selected fields become `[REDACTED]`. Genuinely empty fields remain empty.

### Redaction Boundary

Rules and configured actions continue using the original notification in memory. This preserves content-based matching and template expansion.

Consequently, an external `exec` action can still receive original notification content when its configured arguments reference content templates. That external process is outside Notilog's redaction boundary.

Current redaction does not automatically hide:

- Notification keys.
- AX identifiers or subroles.
- Rule names and user-authored config strings.
- Previously stored database rows.

These are intentional current boundaries, not guarantees that those fields can never be sensitive.

---

## Host and CLI Responsibilities

`notilog-cli` is now a host of `NotilogCore`, not the owner of monitoring behavior.

The CLI owns:

- Command and option parsing.
- `CLIStartupConfiguration` and legacy-default runtime-path selection.
- Accessibility permission checks and `NotificationScanner` construction.
- Retention loading when persistence is enabled.
- Database, session, automation-engine, and monitor assembly.
- Choosing scan and action timestamps.
- The foreground `while true` loop and `Thread.sleep(...)` cadence.
- Terminal-specific rendering through callbacks.
- Human-readable history, rule, validation, and status commands.

`NotificationMonitor` and its lower-level processors/coordinators own:

- Previous-session disappearance recovery.
- Appeared/disappeared event tracking and grace scans.
- Rule matching and action execution.
- Event and action-result persistence.
- Pending dismissal-verification state and evaluation.
- Verification-status persistence.
- The ordering of recovered events, current events, actions, and verification results.

The ShutUpMac app is a production host of this boundary. It supplies a timer-driven lifecycle, Activity presentation, runtime configuration replacement, live persistence/redaction policy, shared retention updates, read-only history access while logging is disabled, typed error presentation, and the in-process dismissal handler. Other hosts can choose different lifecycle, presentation, and dismissal dependencies without changing `NotilogCore`.

## Error and Execution Model

`NotilogError` is the shared typed error contract across `NotilogCore`, the GUI, and the CLI. It distinguishes monitor-lock failures, missing databases, schema migration/compatibility failures, retention configuration failures, database operation failures, and attempted read-only mutation. The GUI maps these cases to concise titles and details. The CLI renders localized descriptions to standard error; malformed command usage exits 2, while runtime failures exit 1.

The current CLI is a synchronous foreground process:

- AX scans occur serially.
- Rule evaluation and action execution occur serially for each event.
- External processes are awaited before the watch loop continues.
- Delayed ShutUpMac checks are represented as pending in-memory records and evaluated during later scans.
- Fatal configuration, database, or permission failures terminate the command.

This model is simple and predictable, but high-latency external actions can delay subsequent scans.

---

## Testing

`NotilogCoreTests` covers the reusable monitoring pipeline without requiring live AX access. Tests use explicit timestamps, in-memory notifications, and temporary SQLite databases.

Coverage includes:

- Notification matching, config conversion, and validation.
- Template expansion and action execution.
- Event recovery, appeared/disappeared tracking, and grace scans.
- Pending dismissal scheduling and due verification evaluation.
- One-cycle result ordering.
- Automation execution modes and rule/action order.
- Event and action-result persistence with redaction and `--no-logging` behavior.
- Mixed unredacted, redacted, and maximum-length persistence in one database.
- Completed verification-status persistence.
- Full `NotificationMonitor` callback ordering and typed results.
- Read-only store behavior, concurrent writer/read-only access, and mutation rejection.
- Explicit schema versioning, recognized migrations, too-new rejection, and unknown-schema rejection.
- Shared retention defaults, validation, atomic replacement, and malformed-file preservation.
- Independent pruning, active-state preservation, and unreferenced ended-session cleanup.
- Logging-disabled automation without database mutation.
- GUI/CLI automation parity through separate processors using the same rules and events.

CLI-level output and option interactions are still validated with process-level smoke tests. The CLI now rejects malformed positive-integer options and missing `--config` values instead of silently falling back.

## GUI Hosting

The ShutUpMac app hosts `NotilogCore` directly:

```text
      ┌───────────────────────────┐
      │ ShutUpMac.app / other UI │
      └─────────────┬─────────────┘
                    │ scans, timestamps, callbacks
                    ▼
            NotificationMonitor
                    │
                    ▼
               NotilogCore
```

The current GUI provides a unified management window with history browsing, Activity-to-Rules drafts, live privacy controls, shared retention settings, database maintenance, and a deliberately limited ordinary-rule editor. Advanced rules remain visible but read-only, and GUI saves preserve unsupported advanced rule fields. Future GUI work may add Activity details or structured filters only if the existing search/table workflow proves insufficient. It should not duplicate event derivation, matching, action execution, persistence coordination, retention, schema handling, errors, or dismissal verification.

The current monitor API is synchronous and nonblocking only in the lifecycle sense: it processes one supplied scan and returns. A host remains responsible for scheduling repeated scans and deciding how cancellation should work.

## Current Boundaries and Likely Next Work

- Define restart behavior for stale `pending` verification rows.
- Add Activity details or structured filters only if the current search/table workflow proves insufficient.
- Audit whether raw notification keys and AX identifiers require hashing or optional redaction.
- Investigate individual child dismissal inside expanded notification stacks only if a dependable AX path emerges; do not assume collapsed stacks can be targeted precisely.
- Add attachment extraction only with an explicit persistence and privacy policy.
- Consider asynchronous action execution only if blocking actions become a practical problem.
- Keep the CLI as a supported host and advanced/debugging surface rather than removing it.

## Guiding Philosophy

Build one reusable notification engine, then make the CLI, database tools, GUI, and integrations clients of that engine.
