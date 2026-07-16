# Changelog

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