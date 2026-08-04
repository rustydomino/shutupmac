# Changelog

## [0.6.0] - 2026-08-04

### Added

- Embedded the reusable Notilog monitoring and automation engine directly in the ShutUpMac app.
- Added searchable, sortable Activity history with recent SQLite records, live updates, matched-rule display, and rule creation from a selected notification.
- Added an ordinary Rules editor with enable/disable, add, edit, delete, exact/contains matching, case sensitivity, and contains-based exceptions.
- Added notification logging and per-field redaction controls for title, subtitle, and body.
- Added database statistics, bounded retention, shared `retention.json` controls, and confirmed Activity-database reset.
- Added `notilog-cli retention show`, `set`, and `reset` commands.
- Added targeted dismissal by runtime Accessibility key and in-process ShutUpMac dismissal for embedded automation.
- Added a single-monitor process lock, explicit SQLite schema versioning, read-only database access, typed core errors, and regression coverage for GUI/CLI parity and persistence safety.

### Changed

- Replaced the standalone preferences presentation with a native macOS Settings window containing General, Hot Keys, Activity, Rules, and Advanced toolbar tabs.
- Compacted the Settings layouts and reduced the default/minimum window width while preserving scrollable Activity and Advanced content.
- Added Finder-style ascending/descending rule-name sorting, alternating rule rows, clearer editable fields, and aligned match/exception controls.
- Made retention values directly typeable and adjustable with native steppers, with a non-destructive Reset to Default action.
- Enforced menu-bar-only operation and removed redundant Activity and Rules commands from the menu-bar menu.
- Aligned ShutUpMac, `shutupmac-cli`, NotilogCore, and `notilog-cli` on version `0.6.0` with app build number `1`.

### Fixed

- Prevented duplicate dismissal attempts when multiple matching rules request the same ShutUpMac action.
- Preserved advanced hand-authored rule fields, actions, exceptions, UUIDs, and stored order during ordinary GUI edits.
- Ensured logging-disabled GUI history access cannot create, migrate, prune, or mutate SQLite, while CLI `watch --no-logging` does not open SQLite at all.
- Rejected malformed numeric CLI options and missing option values instead of silently falling back to defaults.
- Fixed `shutupmac-cli --version` so development and embedded helpers find the correct containing or sibling app metadata.

## [0.5.0] - 2026-07-15

### Added

- Added **Clear Most Recent Notification** action.
  - Default hotkey: `⌃⌥⌘R`.
  - Clears the top visible notification if the most recent visible item is a single notification.
  - Clears the top visible notification stack if the most recent visible item is a stack.
- Added configurable hotkey support for Clear Most Recent Notification.
- Added CLI version flag:
  - `--version`
  - `-v`

### Changed

- Renamed **Clear Visible Notifications** to **Clear Desktop Notifications** in the GUI.
  - Default hotkey changed from `⌃⌥⌘V` to `⌃⌥⌘D`.
- Renamed CLI visible-clear flag to:
  - `--clear-desktop`
  - `-d`
- Kept `--clear-visible` as a legacy CLI alias.
- Changed Dock setting wording from **Hide Dock icon** to **Show Dock icon**.
- Clicking a ShutUpMac test notification no longer leaves the app in the foreground when Dock icon is hidden.

### Fixed

- Improved behavior when interacting with ShutUpMac test notifications while running as a menu-bar-only utility.

## [0.4.0] - 2026-07-14

### Added

- Added separate GUI actions for:
  - Clear Desktop Notifications
  - Clear All Notifications
  - Send Test Notification
- Added configurable global hotkeys.
- Added Settings window.
- Added Launch at Login setting.
- Added command-line helper install command in Settings.
- Added test notification support from the menu bar app.

### Changed

- Split notification-clearing behavior into clearer user-facing actions.
- Improved menu bar app polish and settings behavior.

### Fixed

- Improved Clear All Notifications reliability by targeting the Notification Center **Clear All Notifications** button directly when available.
- Improved visible notification clearing behavior with progress-aware AX polling.

## [0.3.0] - 2026-07-13

### Added

- Added targeted notification actions:
  - Clear top visible single notification.
  - Clear top visible notification stack.
  - List visible notification candidates.
- Added AX diagnostics helpers for Notification Center inspection.

### Changed

- Refactored notification clearing engine into smaller files.

## [0.2.0] - 2026-07-12

### Added

- Added command-line interface for notification clearing.
- Added clear-all support through Accessibility APIs.
- Added debug output options.

## [0.1.0] - 2026-07-11

### Added

- Initial ShutUpMac prototype.
- Basic macOS Notification Center clearing experiment.