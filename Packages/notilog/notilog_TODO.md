# Notilog TODO

_Last updated: 2026-07-24_

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

## Immediate next steps

- [ ] Merge the refactor branch into `main` and run the package tests on the merged branch.
- [ ] Refresh the shared source archive or project upload after the merge.
- [ ] Decide the next product milestone: direct ShutUpMac app hosting or the read-only Activity viewer.
- [ ] Add process-level tests for CLI option parsing and exit codes so malformed-option behavior is automated.

## Library and host integration

- [ ] Integrate `NotificationMonitor` into the ShutUpMac app when the app is ready to own watcher lifecycle.
- [ ] Add a cancellable app-host lifecycle without adding an infinite loop to `NotilogCore`.
- [ ] Decide whether the app and CLI should share a factory/builder for monitor dependency assembly.
- [ ] Preserve the CLI as a supported debugging and operational host.
- [ ] Add structured host events only if callback-based presentation becomes awkward in the GUI.

## Privacy mode

### Global no-persistence mode

- [x] `watch --no-logging` does not open or write SQLite.
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

### Global truncation

- [ ] Add `watch --truncate <length>`.
- [ ] Apply independently to title, subtitle, and body.
- [ ] Count Swift `Character` values, not UTF-8 bytes.
- [ ] Append `…` only when text was shortened.
- [ ] Define `--truncate 0` behavior.
- [ ] Reject negative or invalid lengths with a clear error.
- [ ] Decide and document precedence: `--redact` overrides `--truncate`.
- [ ] Warn that truncation is not strong privacy protection.

### Privacy preset

- [ ] Consider adding `watch --privacy` after truncation and retention semantics are stable.
- [ ] Decide whether it means `--no-logging`, `--redact`, or a documented combination.
- [ ] Avoid adding the preset until its promise is unambiguous.

### Per-rule retention policy

- [ ] Consider a rule schema such as:

```json
"storage": {
  "mode": "inherit"
}
```

- [ ] Candidate modes: `inherit`, `full`, `truncate`, `redact`, and `none`.
- [ ] Evaluate criteria and action templates against full in-memory content before persistence policy is applied.
- [ ] Define deterministic precedence when multiple rules match: `none` > `redact` > `truncate` > `full`.
- [ ] Decide whether retention belongs inside automation rules or in a separate retention-rules system.

## Monitoring lifecycle

- [x] Separate the watch pipeline into explicit scan, event, automation, persistence, and verification stages.
- [x] Support one testable monitoring cycle without AX access.
- [x] Accept explicit scan and action timestamps in reusable core APIs.
- [x] Return typed monitoring results rather than printing inside the core.
- [x] Preserve recovered-event-before-current-event ordering.
- [x] Keep verification functional when logging is disabled.
- [ ] Decide how stale `pending` action rows should be handled when Notilog exits before verification.
- [ ] Candidate final state: `verification_interrupted` or `unknown`.
- [ ] On startup, decide whether to mark stale rows interrupted, recheck recent rows, or leave them pending with an explanation.
- [ ] Consider asynchronous action execution only if synchronous actions cause practical scan delays.

## ShutUpMac integration cleanup

- [ ] Change ShutUpMac to return clearer machine-readable outcome distinctions.
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
| `succeeded` | `pending` | ShutUpMac reported immediate success; delayed check required |
| `uncertain` | `pending` | ShutUpMac acted but saw no immediate progress |
| `failed` | `nil` | ShutUpMac could not perform the action |
| `succeeded` or `uncertain` | `probably_succeeded` | Exact key later disappeared |
| `succeeded` or `uncertain` | `definitely_failed` | Exact key remained visible |

- [x] Avoid claiming definite success when an AX key disappears.
- [x] Preserve `definitely_failed` when the exact key remains visible after the delay.
- [ ] Define restart behavior for pending verifications.
- [ ] Consider storing verification-request and completion timestamps explicitly.

## Database and data model cleanup

- [ ] Add stable rule IDs; do not rely on editable rule names as identity.
- [ ] Store both stable rule ID and execution-time rule name in `action_runs`.
- [ ] Add structured `action_type` to `action_runs`.
- [ ] Avoid making future UI code parse human-readable action summaries.
- [ ] Consider explicit fields for executable, notification key, verification timing, and completion timestamp.
- [ ] Decide whether redacted/truncated records should store the applied privacy mode.
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

### Remaining tests

- [ ] Add process-level tests for missing and malformed CLI option values.
- [ ] Add explicit process tests proving `--quiet` suppresses all routine watch output.
- [ ] Add restart tests for stale/pending verification behavior after that policy is defined.
- [ ] Add Unicode truncation and precedence tests when `--truncate` is implemented.
- [ ] Add per-rule retention precedence tests if retention policy is added.

## First GUI milestone: Activity viewer

- [ ] Build a read-only macOS Activity viewer before a full rule builder.
- [ ] Present a joined narrative rather than separate raw tables:
  - notification appeared
  - rule matched
  - action executed
  - immediate action result
  - delayed verification result
  - notification disappeared
- [ ] Add filters for app, rule, event type, action status, verification status, and time range.
- [ ] Clearly display privacy state for redacted/truncated records.
- [ ] Add a details view for the original stored event/action fields.

## Rules UX

- [ ] Start with a read-only Rules viewer.
- [ ] Show enabled state, match conditions, actions, storage policy, recent match count, and most recent result.
- [ ] Add enable/disable control.
- [ ] Add raw JSON editing as an escape hatch.
- [ ] Add duplicate, delete, and validation before saving.

## Rule builder

- [ ] Prefer “Create rule from this notification” over an empty generic form.
- [ ] Let the user choose which observed fields become match criteria.
- [ ] Show a historical match preview and allow inspection before enabling the rule.
- [ ] Include storage policy after per-rule retention exists.
- [ ] Eventually suggest automation for repeatedly dismissed notifications.

## Documentation and CLI help

- [x] Document `shutupmac_dismiss`.
- [x] Document action and delayed-verification statuses.
- [x] Explain that key disappearance is only probable success.
- [x] Document `--no-logging`, `--quiet`, and `--redact` with examples.
- [x] Document the library-first monitoring architecture and host/core boundary.
- [ ] State clearly whether console output may be retained by the user's terminal or shell environment.
- [ ] Document truncation and all option-precedence rules when truncation is added.

## Suggested implementation order

1. [x] Implement global no-logging and redaction policies.
2. [x] Make runtime paths, startup configuration, and diagnostics host-configurable.
3. [x] Complete the library-first watch-session refactor and one-cycle monitor facade.
4. [x] Update architecture, README, and roadmap documentation.
5. [ ] Merge and refresh the shared source baseline.
6. [ ] Choose direct ShutUpMac app hosting or the Activity viewer as the next milestone.
7. [ ] Add `--truncate <length>` if stronger display/storage minimization is still desired.
8. [ ] Add stable rule IDs and structured action identity.
9. [ ] Resolve stale/pending verification behavior across restart.
10. [ ] Build the Activity viewer, then Rules viewer and rule-builder workflows.
11. [ ] Add per-rule retention policies only after the global privacy pipeline remains stable.
