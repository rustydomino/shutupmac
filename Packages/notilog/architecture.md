# Notilog Architecture

## Project Goal

Notilog is a macOS notification observation, logging, and automation engine built around the Accessibility (AX) API.

The project currently provides a Swift package with:

- `NotilogCore`, a reusable library containing scanning, event tracking, persistence, rule matching, action execution, verification, and redaction logic.
- `notilog-cli`, a command-line client that configures and runs the core engine.

A future GUI should reuse `NotilogCore` rather than reimplement notification scanning or automation behavior.

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
│   ├── Persistence coordinators and SQLite store
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

Schema evolution uses SQLite `PRAGMA user_version` plus targeted migrations.

### Active-State Recovery

When database logging is enabled, watch startup:

1. Creates a new observation session.
2. Loads the prior `active_notifications` set.
3. Performs the first live scan.
4. Emits `disappeared_unobserved` for prior keys that are no longer visible.
5. Continues normal snapshot comparison.

When `--no-logging` is active, the database is not opened, no session is written, and prior active state is not loaded.

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
titleContains
subtitleContains
bodyContains
anyTextContains
caseSensitive
```

One matching rule can produce multiple `AutomationMatch` values when it defines multiple actions.

`NotificationAutomationProcessor` combines rule evaluation with execution-mode selection. It preserves rule-array and action-array order and returns `[ActionRunResult]` without printing or persisting them.

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

It resolves to:

```text
shutupmac-cli --dismiss-key <notification-key>
```

The default helper path is:

```text
/Applications/ShutUpMac.app/Contents/Helpers/shutupmac-cli
```

A rule may override that path with its `command` field.

### Delayed Verification

A successful dismissal request, or the known ShutUpMac "performed but no visible progress" response, schedules a delayed check approximately two seconds later.

The verifier compares the original notification key against the next visible notification set:

```text
key absent  → probably_succeeded
key present → definitely_failed
```

This is intentionally conservative. AX observation can establish that a key remained visible, but absence is treated as probable rather than absolute proof of the cause.

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

This boundary allows the ShutUpMac app or another GUI to host the same monitor while choosing a different lifecycle and presentation layer.

## Error and Execution Model

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
- Completed verification-status persistence.
- Full `NotificationMonitor` callback ordering and typed results.
- SQLite persistence and migrations.

CLI-level output and option interactions are still validated with process-level smoke tests. The CLI now rejects malformed positive-integer options and missing `--config` values instead of silently falling back.

## Future GUI

A future GUI, including the ShutUpMac app, can host `NotilogCore` directly:

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

The GUI may provide rule construction, history browsing, aggregate notification analytics, privacy controls, and action diagnostics. It should not duplicate event derivation, matching, action execution, persistence coordination, or dismissal verification.

The current monitor API is synchronous and nonblocking only in the lifecycle sense: it processes one supplied scan and returns. A host remains responsible for scheduling repeated scans and deciding how cancellation should work.

## Current Boundaries and Likely Next Work

- Integrate `NotificationMonitor` into the ShutUpMac app when the app is ready to own watcher lifecycle.
- Add a cancellable app-host lifecycle without changing the one-cycle core API.
- Build a read-only Activity viewer before a full rule editor.
- Decide how stale `pending` verifications should be handled across process restart.
- Audit whether raw notification keys and AX identifiers require hashing or optional redaction.
- Add attachment extraction only with an explicit persistence and privacy policy.
- Add richer history filtering and structured output formats.
- Consider asynchronous action execution only if blocking actions become a practical problem.
- Keep the CLI as a supported host and debugging surface rather than removing it.

## Guiding Philosophy

Build one reusable notification engine, then make the CLI, database tools, GUI, and integrations clients of that engine.
