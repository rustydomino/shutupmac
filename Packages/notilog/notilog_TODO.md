# Notilog TODO

_Last updated: 2026-07-21_

## Immediate next steps

- [ ] Commit the current ShutUpMac uncertainty-handling work.
  - Suggested commit message: `Handle uncertain ShutUpMac dismiss results`
- [ ] Verify the working tree is clean with `git status --short`.
- [ ] Update the current source archive after the commit so future edits use the latest baseline.

## Privacy mode

### Global no-persistence mode

- [ ] Add `watch --no-logging`.
- [ ] Define it precisely in help text:
  - Do not open or write the SQLite database.
  - Continue normal console output.
  - Continue scanning, matching rules, running actions, and delayed ShutUpMac verification in memory.
  - Disable session history and restart recovery.
- [ ] Refactor `NotificationStore` usage so the watch loop can operate with no store.
- [ ] Make `PendingActionVerification.actionRunID` optional so verification can run without a database row.
- [ ] Ensure these combinations work:
  - `watch --no-logging`
  - `watch --no-logging --dry-run-actions`
  - `watch --no-logging --run-actions`

### Global redaction

- [ ] Add `watch --redact`.
- [ ] Match rules and expand action templates using the original notification in memory.
- [ ] Redact only at output boundaries:
  - SQLite persistence
  - normal console output
  - debug output
  - action stdout/stderr where sensitive content could be echoed
- [ ] Preserve non-content metadata where useful:
  - timestamp
  - event type
  - app
  - AX subrole
  - AX identifier/key
  - rule name
  - action status
  - verification status
- [ ] Replace title, subtitle, and body with a consistent marker such as `[REDACTED]`.

### Global truncation

- [ ] Add `watch --truncate <length>`.
- [ ] Apply independently to title, subtitle, and body.
- [ ] Count Swift `Character` values, not UTF-8 bytes.
- [ ] Append `…` only when text was shortened.
- [ ] Define `--truncate 0` behavior.
- [ ] Reject negative or invalid lengths with a clear error.
- [ ] Decide and document precedence: `--redact` overrides `--truncate`.

### Privacy preset

- [ ] Consider adding `watch --privacy` after the individual options are stable.
- [ ] Decide whether it should mean:
  - `--no-logging`
  - `--redact`
  - or a combination/preset
- [ ] Avoid adding the preset until its promise is unambiguous.

### Per-rule retention policy

- [ ] Add only after the global privacy pipeline exists.
- [ ] Consider a rule schema such as:

```json
"storage": {
  "mode": "inherit"
}
```

- [ ] Candidate modes:
  - `inherit`
  - `full`
  - `truncate`
  - `redact`
  - `none`
- [ ] For truncation, support a per-rule length.
- [ ] Evaluate rule criteria against full notification content before persistence.
- [ ] Define deterministic precedence when multiple rules match:
  - `none` > `redact` > `truncate` > `full`
- [ ] Decide whether storage policy belongs inside automation rules or in a separate retention-rules system.

## Watch-loop architecture cleanup

- [ ] Separate the watch pipeline into explicit stages:
  1. scan full notifications
  2. derive events
  3. evaluate rules using full data
  4. run actions using full data
  5. apply privacy policy to console/database copies
  6. optionally persist
- [ ] Avoid scattering `if !noLogging` checks throughout `main.swift`.
- [ ] Introduce a central options model, for example:

```swift
struct PrivacyOptions {
    let persistenceEnabled: Bool
    let redactText: Bool
    let truncateLength: Int?
}
```

- [ ] Consider a persistence abstraction so the watch loop does not depend directly on SQLite.
- [ ] Ensure observation and automation remain fully functional without persistence.

## ShutUpMac integration cleanup

- [ ] Change ShutUpMac to return machine-readable outcome distinctions.
- [ ] Prefer distinct exit codes over parsing English stderr text, for example:
  - `0`: immediate progress observed
  - `1`: dismissal could not be performed
  - `2`: action performed, immediate outcome uncertain
- [ ] Update Notilog to use those exit codes once ShutUpMac supports them.
- [ ] Remove stderr substring matching after the new CLI contract is available.
- [ ] Consider a future ShutUpMac `--json` result mode if richer diagnostics become useful.
- [ ] Document the division of responsibility:
  - Notilog observes, matches, schedules, verifies, and records.
  - ShutUpMac performs AX dismissal.

## Verification lifecycle

- [ ] Document valid action/verification combinations.

| Action status | Verification status | Meaning |
|---|---|---|
| `dry_run` | `nil` | No action executed |
| `succeeded` | `pending` | SUM reported immediate success; delayed check required |
| `uncertain` | `pending` | SUM acted but saw no immediate progress |
| `failed` | `nil` | SUM could not perform the action |
| `succeeded` or `uncertain` | `probably_succeeded` | Exact key later disappeared |
| `succeeded` or `uncertain` | `definitely_failed` | Exact key remained visible |

- [ ] Decide what happens to `pending` rows when Notilog exits before verification.
- [ ] Candidate final state: `verification_interrupted` or `unknown`.
- [ ] On startup, decide whether to:
  - mark stale pending rows interrupted,
  - recheck only very recent rows,
  - or leave them pending with a clear explanation.
- [ ] Avoid claiming definite success when an AX key disappears, because stacking can hide it.
- [ ] Preserve “definitely failed” when the exact key remains visible after the grace period.

## Database and data model cleanup

- [ ] Add stable rule IDs; do not rely on editable rule names as identity.
- [ ] Store both stable rule ID and execution-time rule name in `action_runs`.
- [ ] Add structured `action_type` to `action_runs`.
- [ ] Avoid making future UI code parse human-readable action summaries.
- [ ] Consider explicit fields for:
  - action type
  - executable
  - notification key
  - verification timing
  - verification completion timestamp
- [ ] Add a migration/versioning strategy that is easy to test and inspect.
- [ ] Decide whether redacted/truncated records should store the applied privacy mode.
- [ ] Consider recording that an event was intentionally not persisted, without retaining its content.

## Tests

### Privacy tests

- [ ] `--no-logging` does not create or modify the database.
- [ ] `--no-logging --run-actions` still runs actions.
- [ ] `--no-logging --run-actions` still performs delayed verification.
- [ ] `--redact` does not change rule matching.
- [ ] `--redact` does not change action template expansion.
- [ ] `--redact` protects SQLite, console, and debug output.
- [ ] `--truncate N` handles Unicode correctly.
- [ ] `--redact` overrides `--truncate`.
- [ ] Per-rule retention precedence is deterministic when multiple rules match.

### Store and migration tests

- [ ] Opening a version-3 database adds `verification_status` correctly.
- [ ] Opening an already migrated database is harmless.
- [ ] Updating a nonexistent action-run ID fails predictably.
- [ ] Redacted/truncated persistence round-trips correctly.

### Verification tests

- [ ] Multiple pending verifications are processed correctly.
- [ ] Checks that are not yet due remain queued.
- [ ] Due checks are removed after evaluation.
- [ ] One database-update failure does not silently discard unrelated queued checks.
- [ ] Pending verification behavior across restart is covered.

## First GUI milestone: Activity viewer

- [ ] Build a read-only macOS Activity viewer before a full rule builder.
- [ ] Present a joined narrative rather than separate raw tables:
  - notification appeared
  - rule matched
  - action executed
  - immediate action result
  - delayed verification result
  - notification disappeared
- [ ] Add filters for:
  - app
  - rule
  - event type
  - action status
  - verification status
  - time range
- [ ] Clearly display privacy state for redacted/truncated records.
- [ ] Add a details view for the original stored event/action fields.

## Rules UX

- [ ] Start with a read-only Rules viewer.
- [ ] Show:
  - enabled state
  - match conditions
  - actions
  - storage/retention policy
  - recent match count
  - most recent execution result
- [ ] Add enable/disable control.
- [ ] Add raw JSON editing as an escape hatch.
- [ ] Add duplicate and delete.
- [ ] Add validation before saving.

## Rule builder

- [ ] Prefer “Create rule from this notification” over an empty generic form.
- [ ] Let the user choose which observed fields become match criteria.
- [ ] Offer candidate criteria such as:
  - app equals
  - title equals/contains
  - subtitle equals/contains
  - body contains
  - event type
- [ ] Show a historical match preview:
  - “This rule would have matched N prior notifications.”
- [ ] Let the user inspect those matching notifications before enabling the rule.
- [ ] Include storage policy in the builder after per-rule retention exists.
- [ ] Eventually suggest automation for repeatedly dismissed notifications.

## Documentation and CLI help

- [ ] Update README for `shutupmac_dismiss`.
- [ ] Document `succeeded`, `uncertain`, and `failed`.
- [ ] Document `pending`, `probably_succeeded`, and `definitely_failed`.
- [ ] Explain that disappearance is only probable success because of macOS stacking.
- [ ] Add privacy-option help and examples.
- [ ] State clearly whether console output is retained by the user’s terminal/shell environment.
- [ ] Warn that `--truncate` is not strong privacy protection.
- [ ] Document all option-precedence rules.

## Suggested implementation order

1. [ ] Commit current ShutUpMac uncertainty handling.
2. [ ] Improve ShutUpMac’s machine-readable exit contract.
3. [ ] Implement `--no-logging` with full in-memory automation and verification.
4. [ ] Create one centralized privacy transformation policy.
5. [ ] Add `--redact`.
6. [ ] Add `--truncate <length>`.
7. [ ] Audit debug output and action stdout/stderr for privacy leaks.
8. [ ] Add stable rule IDs and structured action identity.
9. [ ] Resolve stale/pending verification behavior across restart.
10. [ ] Build the read-only Activity viewer.
11. [ ] Build the Rules viewer and enable/disable controls.
12. [ ] Add “Create rule from notification.”
13. [ ] Add historical match preview.
14. [ ] Add per-rule retention policies.
15. [ ] Consider a documented `--privacy` preset.
