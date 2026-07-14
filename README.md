# ShutUpMac

ShutUpMac is a macOS menu-bar utility and companion CLI for clearing Notification Center notifications without reaching for the mouse.

The project is aimed at people who still want to see notifications, but want a fast keyboard-driven way to get rid of notification clutter.

## Features

- Clear all notifications from Notification Center.
- Clear currently visible notifications.
- Clear the top visible single notification.
- Clear the top visible notification stack.
- List visible notification candidates from the CLI.
- Diagnostic Accessibility tree dump for debugging macOS Notification Center behavior.
- Shared Swift engine used by both the GUI app and CLI helper.

## Requirements

- macOS
- Xcode
- Accessibility permission for the app and/or CLI helper

ShutUpMac controls Notification Center through macOS Accessibility APIs. The app or CLI must be allowed under:

```text
System Settings > Privacy & Security > Accessibility
```

## Project layout

```text
Sources/ShutUpMac/
  ShutUpMac.xcodeproj
  ShutUpMac/
    ShutUpMacEngine.swift
    AXHelpers.swift
    NotificationCenterAccess.swift
    NotificationClearAll.swift
    VisibleNotifications.swift
    AXDiagnostics.swift
  ShutUpMacCLI/
    main.swift
```

Core responsibilities:

```text
ShutUpMacEngine.swift
  Shared config, result types, and public-facing wrappers.

AXHelpers.swift
  Generic Accessibility helper functions.

NotificationCenterAccess.swift
  Finds, opens, and closes Notification Center.

NotificationClearAll.swift
  Robust clear-all behavior for Notification Center.

VisibleNotifications.swift
  Discovery and clearing of visible notifications and stacks.

AXDiagnostics.swift
  Diagnostic AX dump and menu probing tools.

ShutUpMacCLI/main.swift
  Command-line interface.
```

## CLI usage

The CLI target builds a helper that can be run directly or symlinked as `stfu`.

Common commands:

```bash
stfu --clear-all
stfu --clear-visible
stfu --clear-single
stfu --clear-stack
stfu --list-visible
stfu --help
```

Debug and diagnostic commands:

```bash
stfu --clear-all --debug
stfu --clear-visible --debug
stfu --ax-dump
stfu --ax-dump --probe-menus
```

Short flags are also available for common actions:

```bash
stfu -a   # clear all
stfu -v   # clear visible
stfu -n   # clear top single notification
stfu -s   # clear top visible stack
stfu -l   # list visible notifications
stfu -q   # quiet output
```

## GUI behavior

The GUI is a macOS menu-bar app. The long-term goal is to expose the most useful actions directly from the menu bar, while keeping diagnostic tooling mostly in the CLI.

Recommended product-level actions:

```text
Clear Visible Notifications
Clear All Notifications
```

Possible advanced actions:

```text
Clear Top Notification
Clear Top Stack
Show Visible Notifications
```

## Building

Open the Xcode project:

```bash
open Sources/ShutUpMac/ShutUpMac.xcodeproj
```

Build the GUI app target and the CLI target separately:

```text
ShutUpMac
ShutUpMacCLI
```

Make sure shared source files are included in both targets when needed.

## Testing checklist

Useful manual smoke tests:

```bash
stfu --help
stfu --list-visible
stfu --clear-visible --debug
stfu --clear-single
stfu --clear-stack
stfu --clear-all --debug
stfu --ax-dump
```

Recommended scenarios:

- No visible notifications.
- One visible notification.
- Multiple visible notifications.
- One collapsed notification stack.
- Notification Center closed before running the command.
- Notification Center already open before running the command.
- Notification Center filled vertically with many notifications.

## Notes

Notification Center's Accessibility structure can change across macOS releases. The diagnostic commands exist to inspect what macOS is exposing when behavior changes.

`--clear-all` is intended to be the robust/nuclear path. `--clear-visible` is intentionally more targeted and may take longer when many notifications are visible because it waits for UI progress between actions.

## License

ShutUpMac is licensed under the GNU General Public License version 2.0. See [LICENSE](LICENSE).
