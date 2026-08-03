# Notilog TODO

_Last updated: 2026-08-03_

## Completed foundations

- [x] Integrate Notilog as a local Swift package inside the ShutUpMac repository.
- [x] Keep `NotilogCore` as a reusable library product and `notilog-cli` as a host executable.
- [x] Add host-configurable runtime paths through `NotilogRuntimePaths` while preserving the CLI's legacy default location.
- [x] Add explicit CLI startup configuration for paths, logging, redaction, action mode, timing, quiet mode, and debug mode.
- [x] Replace process-global debug state with a host-supplied `DiagnosticHandler`.
- [x] Implement `--no-logging` while preserving event detection, actions, and delayed verification in memory.
- [x] Implement global `--redact` at Notilog-owned console and persistence boundaries.
- [x] Add the dedicated `shutupmac_dismiss` action and delayed verification states.
- [x] Complete the Phase 4 library-first watch-session refactor.
- [x] Add `NotificationMonitor.processScan(...)` as the reusable one-cycle facade.
- [x] Move event tracking, recovery, automation, persistence coordination, and verification state out of `main.swift`.
- [x] Keep the CLI responsible for AX scanning, timestamps, terminal rendering, looping, and sleeping.
- [x] Reject malformed positive-integer CLI values instead of silently using defaults.
- [x] Reject a missing `--config` value.
- [x] Embed `NotificationMonitor` in the ShutUpMac app with app-owned start/stop lifecycle.
- [x] Add a read-only Activity window that loads recent SQLite history and appends live notification activity.
- [x] Add a GUI switch for enabling and disabling notification logging while rules and actions continue.
- [x] Add GUI redaction controls for title, subtitle, and body.
- [x] Apply GUI redaction to subsequent Activity rows and SQLite writes without restarting monitoring.
- [x] Add stable UUIDs to automation configuration rules and preserve identity/order during GUI edits.
- [x] Build the Rules viewer and ordinary-rule editor with enable/disable, add, edit, delete, exact/contains matching, and exceptions.
- [x] Keep advanced event matching, field matching, and actions visible but read-only in the GUI.
- [x] Suppress duplicate dismissal attempts when multiple rules match one notification event.
- [x] Inject in-process dismissal into the ShutUpMac app while retaining the external-helper fallback for standalone hosts.
- [x] Complete manual runtime regression testing for exceptions, disabled rules, exact/contains and case-sensitive matching, logging-disabled automation, redaction boundaries, edit preservation, advanced-rule safety, config-save rollback, and restart persistence.
- [x] Add true read-only `NotificationStore` access that never creates, migrates, prunes, or mutates.
- [x] Add explicit SQLite schema versioning and safe rejection of newer, unknown, or migration-required read-only schemas.
- [x] Add shared typed `NotilogError` cases for monitoring, schema, retention, database, and read-only failures.
- [x] Add shared atomic `retention.json` configuration with GUI migration from non-default legacy preferences.
- [x] Add `notilog-cli retention show`, `set`, and `reset`.
- [x] Make historical event pruning independent from action history and active notification state.
- [x] Remove unreferenced ended watch sessions after historical event pruning.
- [x] Add advanced-rule GUI round-trip regression coverage.
- [x] Add mixed unredacted, redacted, and truncated persistence coverage.
- [x] Enforce logging-disabled guarantees for GUI read-only history and CLI no-open/no-write mode.
- [x] Add GUI/CLI automation parity regression coverage against the shared core.

## Immediate next steps

- [ ] Run clean full-suite and installed-app release validation.
- [ ] Update the project changelog and version for the next release.
- [ ] Define stale/pending verification restart behavior only if it becomes a practical source of misleading history.
- [ ] Add Activity details or structured filters only if the current search/table workflow proves insufficient.

## Library and host integration

- [x] Integrate `NotificationMonitor` into the ShutUpMac app with app-owned watcher lifecycle.
- [x] Add a cancellable timer-driven app host without adding an infinite loop to `NotilogCore`.
- [x] Preserve the CLI as a supported debugging and operational host.
- [x] Load historical appearance records and publish live monitoring results to the Activity store.
- [x] Allow the app host to replace automation configuration, logging state, and redaction policy at runtime.
- [x] Allow a host to inject notification dismissal while preserving the CLI's external-helper fallback.
- [ ] Decide whether the app and CLI should share a factory/builder for monitor dependency assembly.
- [ ] Add structured host events only if callback-based presentation becomes awkward in the GUI.

## Privacy mode

### Global no-persistence mode

- [x] `watch --no-logging` does not create, open, migrate, prune, or write SQLite.
- [x] Continue scanning, matching rules, running actions, and delayed verification in memory.
- [x] Disable session history and restart recovery when no store is present.
- [x] Support:
  - `watch --no-logging`
  - `watch --no-logging --dry-run-actions`
  - `watch --no-logging --run-actions`

### Global redaction

- [x] Add `watch --redact` with default, `all`, and explicit field selections.
- [x] Match rules and expand action templates using the original notification in memory.
- [x] Apply redaction to Notilog-owned event/action console output and SQLite writes.
- [x] Suppress captured action stdout/stderr when redaction is enabled.
- [x] Preserve operational metadata needed for diagnostics and verification.
- [x] Leave genuinely empty selected fields empty.
- [x] Expose title, subtitle, and body redaction in ShutUpMac Settings.
- [x] Disable the GUI redaction controls when notification logging is disabled while preserving saved selections.
- [x] Apply live GUI policy changes to both persistence coordinators and Activity presentation.
- [x] Keep the application name visible in the GUI redaction mode.

### Global truncation

- [x] Decide not to implement `watch --truncate <length>` at this time.
- [x] Keep the privacy model centered on explicit no-logging and redaction controls.
- [x] Avoid presenting truncation as strong privacy protection.
- [ ] Revisit only if a concrete display or storage-minimization requirement emerges.

### Privacy preset

- [ ] Consider a named privacy preset only if the explicit no-logging and redaction controls become unwieldy.
- [ ] Decide whether it means `--no-logging`, `--redact`, or a documented combination.
- [ ] Avoid adding the preset until its promise is unambiguous.

### Per-rule retention policy

- [ ] Consider a rule schema such as:

```json
"storage": {
  "mode": "inherit"
}
```

- [ ] Candidate modes: `inherit`, `full`, `redact`, and `none`.
- [ ] Evaluate criteria and action templates against full in-memory content before persistence policy is applied.
- [ ] Define deterministic precedence when multiple rules match: `none` > `redact` > `full`.
- [ ] Decide whether retention belongs inside automation rules or in a separate retention-rules system.

## Monitoring lifecycle

- [x] Separate the watch pipeline into explicit scan, event, automation, persistence, and verification stages.
- [x] Support one testable monitoring cycle without AX access.
- [x] Accept explicit scan and action timestamps in reusable core APIs.
- [x] Return typed monitoring results rather than printing inside the core.
- [x] Preserve recovered-event-before-current-event ordering.
- [x] Keep verification functional when logging is disabled.
- [x] Keep existing GUI history readable through a read-only store while logging is disabled.
- [x] Do not create a missing GUI database or apply retention merely to inspect disabled-logging history.
- [ ] Decide how stale `pending` action rows should be handled when Notilog exits before verification.
- [ ] Candidate final state: `verification_interrupted` or `unknown`.
- [ ] On startup, decide whether to mark stale rows interrupted, recheck recent rows, or leave them pending with an explanation.
- [ ] Consider asynchronous action execution only if synchronous actions cause practical scan delays.

## ShutUpMac integration cleanup

- [x] Use the in-process ShutUpMac dismissal API when Notilog runs inside the app.
- [x] Keep the external `shutupmac-cli --dismiss-key` path as the standalone fallback.
- [x] Prevent multiple matching dismissal rules from issuing duplicate dismissal attempts for one event.
- [ ] Change the standalone ShutUpMac CLI to return clearer machine-readable outcome distinctions.
- [ ] Prefer distinct exit codes over parsing English stderr text, for example:
  - `0`: immediate progress observed
  - `1`: dismissal could not be performed
  - `2`: action performed, immediate outcome uncertain
- [ ] Update Notilog to use the improved contract once ShutUpMac supports it.
- [ ] Remove stderr substring matching after the new CLI contract is available.
- [ ] Consider a future ShutUpMac `--json` result mode if richer diagnostics become useful.
- [x] Document the current division of responsibility:
  - Notilog observes, matches, schedules, verifies, and records.
  - ShutUpMac performs AX dismissal.

## Verification lifecycle

- [x] Document valid action and verification combinations.

| Action status | Verification status | Meaning |
|---|---|---|
| `dry_run` | `nil` | No action executed |
| `succeeded` | `pending` | External helper accepted the request; delayed check required |
| `uncertain` | `pending` | ShutUpMac acted but saw no immediate progress |
| `succeeded` | `probably_succeeded` | In-process handler reported a clear, or a delayed check found the key absent |
| `failed` | `definitely_failed` | In-process handler reported failure |
| `succeeded` or `uncertain` | `definitely_failed` | Delayed check found the exact key still visible |
| `failed` | `nil` | An action could not start or complete before dismissal verification applied |

- [x] Avoid claiming definite success when an AX key disappears.
- [x] Preserve `definitely_failed` when the exact key remains visible after the delay.
- [ ] Define restart behavior for pending verifications.
- [ ] Consider storing verification-request and completion timestamps explicitly.

## Database and data model cleanup

- [x] Add explicit `readWrite` and `readOnly` store modes.
- [x] Use `PRAGMA user_version` as an explicit schema contract.
- [x] Migrate only recognized legacy schemas and only through a writer.
- [x] Reject newer, unrecognized, or migration-required read-only schemas safely.
- [x] Share validated retention limits through atomic `retention.json`.
- [x] Preserve action history and active notification state while pruning notification events.
- [x] Remove ended sessions only when no retained historical event references them.
- [x] Add stable UUIDs to automation configuration rules; do not rely on editable rule names as configuration identity.
- [ ] Store both stable rule ID and execution-time rule name in `action_runs`.
- [ ] Add structured `action_type` to `action_runs`.
- [ ] Avoid making future UI code parse human-readable action summaries.
- [ ] Consider explicit fields for executable, notification key, verification timing, and completion timestamp.
- [ ] Decide whether redacted records should store the applied privacy mode and selected fields.
- [ ] Consider recording that an event was intentionally not persisted without retaining its content.

## Tests

### Completed reusable-core coverage

- [x] Event recovery and appeared/disappeared grace behavior.
- [x] Pending-verification scheduling, due checks, success/failure evaluation, and queue order.
- [x] One-cycle monitoring result separation and ordering.
- [x] Automation disabled/dry-run/real modes and rule/action order.
- [x] Event persistence with optional store, redaction, session identity, and order.
- [x] Action-result persistence, redaction, optional IDs, and verification scheduling.
- [x] Completed verification-status persistence.
- [x] Full `NotificationMonitor` callback and result ordering.
- [x] Temporary-database tests avoid the user's real Application Support directory.
- [x] Exact title, subtitle, and body matching plus exception decoding/matching.
- [x] Immutable configuration helpers for enable/disable, add, replace, and remove.
- [x] Injected dismissal handler precedence and external-helper fallback.
- [x] Duplicate matching dismissal rules invoke the injected handler only once.
- [x] Read-only database open, missing-file, migration refusal, mutation rejection, and concurrent-reader coverage.
- [x] Explicit schema current/legacy/too-new/unrecognized coverage.
- [x] Shared retention missing/default, validation, malformed preservation, save/load, and atomic replacement coverage.
- [x] Independent pruning, active-state preservation, database reset, and orphan-session cleanup coverage.
- [x] Advanced-rule GUI save-path round-trip coverage.
- [x] Mixed unredacted, redacted, and truncated event/action persistence coverage.
- [x] GUI logging-disabled history/no-create/no-prune coverage.
- [x] No-logging automation-without-database-mutation coverage.
- [x] GUI/CLI automation parity coverage.

### Remaining tests

- [ ] Add process-level tests for missing and malformed CLI option values.
- [ ] Add explicit process tests proving `--quiet` suppresses all routine watch output.
- [ ] Add restart tests for stale/pending verification behavior after that policy is defined.
- [x] Add app-level tests for logging-state transitions and redaction preference mapping.
- [x] Add Activity factory tests for selected-field redaction and action-result suppression.
- [ ] Add per-rule retention precedence tests if retention policy is added.

## First GUI milestone: Activity viewer

- [x] Build a read-only macOS Activity viewer before a full rule builder.
- [x] Load up to 1,000 recent notification appearance records from SQLite.
- [x] Append live notification activity from the embedded Notilog monitor.
- [x] Present app, notification preview, matched rules, and appearance time in a sortable table.
- [x] Add full-text Spotlight-style search across notification records.
- [x] Retain existing history through read-only access while logging is disabled and suppress new Activity rows.
- [x] Avoid schema migration, retention pruning, or database creation merely to display disabled-logging history.
- [x] Display GUI-selected redacted fields as `[REDACTED]`.
- [ ] Add a details/inspector view that presents the joined lifecycle narrative:
  - notification appeared
  - rule matched
  - action executed
  - immediate action result
  - delayed verification result
  - notification disappeared
- [ ] Add structured filters for app, rule, event type, action status, verification status, and time range.
- [ ] Display applied privacy state explicitly rather than relying only on `[REDACTED]` values.

## Rules UX

- [x] Build the read-only Rules viewer.
- [x] Show enabled state, positive match conditions, exceptions, advanced matching, and advanced actions.
- [x] Add enable/disable control for ordinary rules.
- [x] Add ordinary-rule creation, editing, deletion, validation, and atomic save-and-activate behavior.
- [x] Preserve UUID, exceptions, sidebar position, and unsupported advanced fields/actions during ordinary GUI editing.
- [x] Keep unsupported advanced rules read-only and prevent toggling or deletion through the GUI.
- [ ] Polish the functional Rules-window layout and spacing.
- [ ] Consider recent match count and most recent action result only after the Activity/details data path exists.
- [ ] Keep raw JSON or CLI configuration as the escape hatch for advanced users rather than broadening the GUI prematurely.

## Rule builder

- [x] Provide a minimal generic form for ordinary dismissal rules.
- [x] Support exact app matching; exact/contains title, subtitle, and body matching; case sensitivity; and contains-based exceptions.
- [ ] Add “Create rule from this notification” as the preferred contextual workflow.
- [ ] Show a historical match preview and allow inspection before enabling the rule.
- [ ] Include storage policy only if per-rule retention is added.
- [ ] Eventually suggest automation for repeatedly dismissed notifications.

## Known platform limitations

- [x] Record that collapsed notification stacks are represented as one AX element with a Clear All action.
- [x] Accept current stack-clearing behavior rather than silently skipping matching rules; Activity/database logging preserves the observed notifications when logging is enabled.
- [ ] Investigate per-child dismissal only if expanded stacks expose stable, individually actionable child elements across supported macOS versions.

## Documentation and CLI help

- [x] Document `shutupmac_dismiss`.
- [x] Document action and delayed-verification statuses.
- [x] Explain that key disappearance is only probable success.
- [x] Document `--no-logging`, `--quiet`, and `--redact` with examples.
- [x] Document the library-first monitoring architecture and host/core boundary.
- [x] Document the ShutUpMac Activity, logging, and GUI redaction behavior.
- [x] Document the ordinary Rules GUI, advanced-rule read-only boundary, in-process dismissal, and standalone fallback.
- [x] Document read-only database access, explicit schema behavior, typed errors, and shared retention.
- [x] Document the intentional difference between CLI `--no-logging` and GUI logging-disabled history access.
- [x] Record the AX stack limitation: a matching stacked notification may clear older nonmatching notifications in the same stack.
- [x] Record that global truncation is intentionally out of scope for now.
- [ ] State clearly whether console output may be retained by the user's terminal or shell environment.

## Suggested implementation order

1. [x] Implement global no-logging and redaction policies.
2. [x] Make runtime paths, startup configuration, and diagnostics host-configurable.
3. [x] Complete the library-first watch-session refactor and one-cycle monitor facade.
4. [x] Integrate the monitor into ShutUpMac with app-owned lifecycle.
5. [x] Build the first read-only Activity viewer with historical and live records.
6. [x] Add live GUI control of notification logging.
7. [x] Add live GUI redaction for title, subtitle, and body.
8. [x] Add app-level automated regression tests for logging, redaction, Activity presentation, configuration rollback, and Rules presentation.
9. [ ] Add Activity details and structured filtering.
10. [x] Build the read-only Rules viewer, followed by ordinary-rule editing and creation.
11. [x] Add stable configuration rule IDs; structured action identity in `action_runs` remains open.
12. [ ] Resolve stale/pending verification behavior across restart.
13. [ ] Add per-rule retention policies only after the global privacy pipeline remains stable.
14. [x] Complete read-only/schema/error/retention and parity hardening.

Global truncation is not currently planned; revisit it only if a concrete product requirement justifies the additional policy complexity.
