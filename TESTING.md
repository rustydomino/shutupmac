# ShutUpMac Manual Testing Checklist

Use this checklist before and after refactors, especially when changing `ShutUpMacEngine.swift`, CLI routing, or Accessibility logic.

## Build sanity

- [ ] App target builds.
- [ ] ShutUpMac CLI target builds.
- [ ] `swift test --package-path Packages/notilog` passes.
- [ ] The complete ShutUpMac Xcode test target passes.
- [ ] `stfu --help` / `shutupmac-cli --help` prints usage.
- [ ] Unknown flags fail cleanly with usage.
- [ ] `--debug` is quiet enough to read.
- [ ] `--ax-dump` works as a diagnostic action.
- [ ] `--probe-menus` is rejected unless used with `--ax-dump`.

## Accessibility permission

- [ ] If Accessibility permission is missing, the tool fails clearly.
- [ ] If Accessibility permission is granted, normal actions run without prompting.
- [ ] App and CLI behavior are checked separately if they use different signed binaries.

## No-notification state

Run with no visible notifications and no meaningful Notification Center items.

- [ ] `--list-visible` reports no visible notification candidates.
- [ ] `--clear-visible` exits successfully or cleanly reports nothing to clear.
- [ ] `--clear-single` reports no visible single notification.
- [ ] `--clear-stack` reports no visible stack.
- [ ] `--clear-all` does not crash or hang.

## One visible notification

Generate one visible notification.

- [ ] `--list-visible` shows one `single` candidate.
- [ ] `--clear-single` closes it.
- [ ] `--clear-visible` closes it.
- [ ] `--clear-all` clears it through Notification Center.

## Multiple visible notifications

Generate several visible notifications from the same test source.

- [ ] `--list-visible` shows the expected visible `single` candidates.
- [ ] `--clear-visible` clears all visible notifications.
- [ ] `--clear-visible --debug` shows concise progress logs.
- [ ] It does not spam full AX tree dumps during polling.
- [ ] Final result reports AX actions and observed progress events.

## One visible stack

Generate enough notifications to create a visible stack.

- [ ] `--list-visible` shows a `stack` candidate.
- [ ] `--clear-stack` clears the top visible stack.
- [ ] `--clear-visible` can clear the visible stack path.
- [ ] `--clear-all` clears the stack through Notification Center.

## Notification Center closed

Start with Notification Center closed.

- [ ] `--clear-all` opens Notification Center.
- [ ] It finds the direct `Clear All Notifications` AX button when available.
- [ ] It falls back to the xmark/menu path if needed.
- [ ] It closes Notification Center afterward.

## Notification Center already open

Start with Notification Center already open.

- [ ] `--clear-all` works without getting confused by the already-open state.
- [ ] It preserves or restores the expected Notification Center state afterward.
- [ ] `--ax-dump` can inspect the open Notification Center.

## Notification Center filled / overflow case

Create enough notifications that Notification Center fills vertically.

- [ ] The bottom/global control appears visually as the useful clear-all control.
- [ ] `--ax-dump` finds an `AXButton` with description `Clear All Notifications`.
- [ ] `--clear-all --debug` uses the direct clear-all button path.
- [ ] `--clear-all` clears the filled Notification Center case.
- [ ] The top stack/app-group `Clear` button is not mistaken for global clear-all.

## AX dump diagnostics

With Notification Center open:

- [ ] `--ax-dump` prints suspicious clear/x/close controls.
- [ ] `--ax-dump` does not perform `AXShowMenu`.
- [ ] `--ax-dump --probe-menus` performs menu probing.
- [ ] `--ax-dump --probe-menus` may perturb Notification Center; this is expected.
- [ ] Diagnostic output includes role, subrole, title, description, identifier, frame, actions, reasons, and path.

## Hotkey / app behavior

From the menu-bar app:

- [ ] Clear Visible hotkey invokes the visible sweep.
- [ ] Clear All hotkey invokes the robust Notification Center clear-all path.
- [ ] Menu items match CLI behavior.
- [ ] Failures are surfaced without crashing the app.
- [ ] App remains responsive after repeated clears.


## Notification activity, privacy, and database safety

Use disposable Activity data when testing reset or lower retention limits.

- [ ] With logging enabled, a new notification appears in Activity and SQLite.
- [ ] Disable logging and confirm new notifications are still scanned and matching rules still run.
- [ ] While logging is disabled, confirm existing Activity history remains visible.
- [ ] Confirm opening existing history while logging is disabled does not prune records when the configured retention limit is lower.
- [ ] With no database present, start with logging disabled and confirm no database is created.
- [ ] Re-enable logging and confirm a new writable monitoring session starts and new records are persisted.
- [ ] Change redaction fields and confirm only subsequent Activity/database records use `[REDACTED]`.
- [ ] Confirm old unredacted rows remain unchanged.
- [ ] In Advanced, verify database statistics update and paths are correct.
- [ ] Lower retention limits using disposable history and confirm only the oldest excess historical rows are removed.
- [ ] Confirm action history and active notification state are not removed by notification-event pruning.
- [ ] Increase retention limits and confirm no existing rows are removed.
- [ ] Reset the Activity database and confirm rules and app settings remain intact.

CLI retention checks:

```bash
notilog-cli retention show
notilog-cli retention set --events 25000 --actions 10000
notilog-cli retention reset
```

- [ ] `retention show` reports built-in defaults when `retention.json` is missing without creating the file.
- [ ] Invalid `retention set` values exit with usage status 2 and preserve the existing file.
- [ ] A malformed `retention.json` is reported and not overwritten implicitly.
- [ ] `history` and `action-history` do not create a missing database or mutate an existing one.
- [ ] `watch --no-logging` does not create, open, migrate, prune, or write SQLite.
- [ ] `watch --no-logging --run-actions` still evaluates rules and executes enabled actions.

## Rules compatibility

- [ ] Create or retain one advanced hand-authored rule in `config.json`.
- [ ] Add or edit an ordinary rule through the GUI.
- [ ] Confirm the advanced rule keeps its UUID, order, criteria, exceptions, and actions byte-for-byte semantically.
- [ ] Confirm the same ordinary rule and notification produce matching action outcomes through the embedded GUI host and standalone CLI host.

## Regression guardrails

After any refactor:

- [ ] Re-run at least: no notifications, one notification, multiple visible notifications, one stack, filled Notification Center.
- [ ] Confirm `--clear-all`, `--clear-visible`, `--list-visible`, and `--ax-dump` still work.
- [ ] Confirm debug output remains concise.
- [ ] Commit only after the manual checklist passes for the changed area.

## Useful commands

```bash
# Help
./shutupmac-cli --help

# Concise operational debug
./shutupmac-cli --clear-all --debug
./shutupmac-cli --clear-visible --debug

# Visible candidates
./shutupmac-cli --list-visible

# Diagnostics
./shutupmac-cli --ax-dump
./shutupmac-cli --ax-dump --probe-menus

# Capture logs
./shutupmac-cli --clear-all --debug > clear-all-debug.txt 2>&1
./shutupmac-cli --clear-visible --debug > clear-visible-debug.txt 2>&1
./shutupmac-cli --ax-dump --probe-menus > ax-dump.txt 2>&1
```

## Notes

Current intended behavior:

- `--clear-all` is the robust path. It should prefer the direct `AXButton desc == "Clear All Notifications"` path and fall back to the older xmark/menu route.
- `--clear-visible` is a non-invasive sweep of currently visible notifications. It is useful but not guaranteed to feel instant for many items.
- `--clear-single` and `--clear-stack` are precise/power-user actions.
- `--ax-dump` and `--probe-menus` are diagnostic tools, not normal product behavior.
