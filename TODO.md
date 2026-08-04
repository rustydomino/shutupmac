# ShutUpMac TODO

_Last updated: 2026-08-04_

## Project status

ShutUpMac is functionally feature complete for its current intended scope. The
native Settings window, embedded Notilog runtime, ordinary Rules editor,
Activity-to-Rules workflow, privacy controls, retention controls, and database
maintenance tools are implemented.

The August data-safety, regression-hardening, and GUI-polish milestones are
complete. Version `0.6.0` is aligned across the app, both CLIs, and
NotilogCore. Current work is release packaging and validation. Future product
work should remain driven by concrete bugs or recurring user needs rather than
feature expansion.

## Guiding principles

- **STFU:** matching notifications should disappear with minimal friction.
- **KISS:** avoid settings, modes, abstractions, and edge-case machinery unless
  they solve a clear and recurring problem.
- Keep ordinary GUI use separate from advanced CLI/configuration workflows.
- Prefer small, focused changes with a narrow test after each step.
- Preserve the shared `NotilogCore` behavior used by the app and CLI.

## Completed product milestones

- [x] Provide one native macOS Settings window with five toolbar tabs:
  - General
  - Hot Keys
  - Activity
  - Rules
  - Advanced
- [x] Keep the menu-bar menu focused on Settings and core dismissal actions.
- [x] Keep About in a separate small window.
- [x] Provide configurable global hotkeys and launch-at-login control.
- [x] Embed the Notilog watcher directly in the app.
- [x] Keep the standalone `notilog-cli` host available for diagnostics and
      advanced workflows.
- [x] Provide searchable, sortable Activity history with live updates.
- [x] Preserve existing Activity history while notification logging is disabled.
- [x] Provide ordinary-rule add, edit, delete, enable, and disable operations.
- [x] Preserve advanced rules without exposing unsupported editing controls.
- [x] Add **Create Rule from Notification** without automatically saving the
      draft.
- [x] Add global rules-based auto-dismiss enable/disable control.
- [x] Add title, subtitle, and body redaction controls.
- [x] Add database statistics, retention controls, and confirmed Activity
      database reset in the Advanced tab.
- [x] Keep the GUI dismissal path in-process instead of invoking
      `shutupmac-cli`.
- [x] Compact the Settings window to an 860-point minimum width while keeping
      Activity and Advanced scrollable.
- [x] Add Finder-style rule-name sorting, alternating rows, clearer editable
      fields, and aligned match/exception controls.
- [x] Add directly editable retention fields, native steppers, and Reset to
      Default behavior.

## Completed data-safety foundations

- [x] Add true read-only `NotificationStore` access.
  - Read-only access never creates a missing database.
  - Read-only access never migrates or prunes.
  - Public mutation attempts return a typed read-only error.
- [x] Add explicit SQLite schema versioning with `PRAGMA user_version`.
  - Current schemas open normally.
  - Recognized legacy schemas migrate only through a writer.
  - Read-only callers reject schemas that require migration.
  - Newer or unrecognized schemas fail safely.
- [x] Replace database and monitoring string errors with shared typed
      `NotilogError` cases.
- [x] Add shared, validated `retention.json` configuration for the GUI and CLI.
- [x] Migrate non-default legacy GUI retention preferences once, while leaving
      built-in defaults file-free.
- [x] Add `notilog-cli retention show`, `set`, and `reset`.
- [x] Keep notification-event pruning independent from action-run pruning.
- [x] Remove ended watch sessions only when no historical event references them.
- [x] Preserve active notification state while pruning historical records.
- [x] Verify Activity database reset clears historical and active state and
      starts a new session.
- [x] Verify ordinary GUI edits preserve advanced CLI rule fields, actions,
      exceptions, order, and UUIDs.
- [x] Add mixed unredacted, redacted, and truncated persistence coverage.
- [x] Enforce logging-disabled database guarantees.
  - GUI: existing history remains readable through a read-only connection.
  - GUI: opening history does not prune, migrate, or create a database.
  - CLI `watch --no-logging`: SQLite is not opened or modified at all.
  - Rules, actions, and in-memory verification continue without persistence.
- [x] Add GUI/CLI automation parity regression coverage against the shared core.

## Release-hardening checklist

- [x] Align ShutUpMac, `shutupmac-cli`, NotilogCore, and `notilog-cli` on
      version `0.6.0`; set app build number `1`.
- [x] Add the `0.6.0` changelog and refresh current project documentation.
- [ ] Create distribution-ready default `config.json` and `retention.json`
      files.
- [ ] Run the full Notilog package test suite from a clean checkout.
- [ ] Run the complete ShutUpMac Xcode test target.
- [ ] Build both the ShutUpMac and ShutUpMacCLI schemes in Release
      configuration.
- [ ] Produce, sign, and notarize the distributable app as applicable.
- [ ] Smoke-test the installed app with Accessibility and notification
      permissions granted.
- [ ] Smoke-test a clean first launch with the distribution defaults and no
      existing Application Support data.
- [ ] Smoke-test logging enable/disable transitions against an existing database.
- [ ] Smoke-test retention Apply, CLI retention commands, and Activity database
      reset using disposable data.
- [ ] Confirm ordinary Rules edits still preserve an advanced hand-authored rule.
- [ ] Create tag `v0.6.0`, publish the GitHub release, and download-test the
      uploaded artifact.

## Deferred work requiring a concrete need

- [ ] Define restart behavior for stale `pending` dismissal verifications.
- [ ] Improve the standalone ShutUpMac CLI outcome contract with structured or
      distinct machine-readable results if stderr parsing becomes a practical
      problem.
- [ ] Add Activity details or structured filters only if search and the current
      table prove insufficient.
- [ ] Consider asynchronous external action execution only if synchronous
      actions cause measurable scan delays.
- [ ] Investigate individually dismissing children of expanded notification
      stacks only if macOS exposes a dependable AX path.
- [ ] Consider attachment capture only together with an explicit privacy and
      persistence policy.

## Explicitly out of scope unless reopened

- Global auto-dismiss-all / nuclear option.
- Per-rule dismissal delay.
- Script-action editing in the GUI.
- Disappearance-event editing in the GUI.
- Broad advanced field/event builders.
- Complex stack-skipping behavior.
- Global truncation as a configurable privacy mode.
- Additional privacy presets that merely rename existing controls.
- Finder-style Activity complexity without a demonstrated need.

## Accepted platform limitation

When macOS exposes multiple notifications from one application as a collapsed
Accessibility notification stack, the available action may operate like Clear
All for that application's stack. A rule matching one notification can therefore
clear other notifications in the same stack.

This remains an accepted macOS Accessibility limitation. Activity/database
logging reduces its practical impact. Do not add complex stack-skipping logic
unless this decision is explicitly reopened.

## Working style

For each implementation step:

1. Explain the purpose of the change.
2. Provide the file path and approximate line numbers.
3. Include enough surrounding code to locate the edit.
4. Make one focused change at a time.
5. Build or run the narrowest relevant test.
6. Manually verify user-facing behavior where automation cannot cover it.
7. Commit at meaningful, stable milestones.

## Next action

Create the distribution default files, complete the Release build and
installed-app validation, then publish GitHub release `v0.6.0`. New features
should remain deferred until a concrete recurring problem justifies them.
