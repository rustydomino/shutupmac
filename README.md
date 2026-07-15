# ShutUpMac

ShutUpMac is a small macOS menu bar utility for clearing Notification Center notifications from the keyboard or menu bar.

It is built around Accessibility automation. The goal is simple: let you keep your hands on the keyboard while clearing notification clutter.

## Features

### Menu bar app

- Clear visible notifications
- Clear all notifications
- Send a test notification
- Configurable global hotkeys
- Optional menu-bar-only mode with hidden Dock icon
- Optional launch at login
- Built-in command line helper install command

### Default global hotkeys

| Action | Default shortcut |
| --- | --- |
| Clear Visible Notifications | `Control` + `Option` + `Command` + `V` |
| Clear All Notifications | `Control` + `Option` + `Command` + `A` |
| Send Test Notification | `Control` + `Option` + `Command` + `T` |

Hotkeys can be changed in Settings.

### Command line helper

The bundled CLI helper can be installed from the Settings window. By default, the helper is named:

```sh
shutupmac-cli
```

You can also symlink it under a shorter name such as:

```sh
stfu
```

Supported CLI actions include:

```sh
shutupmac-cli --clear-all
shutupmac-cli --clear-visible
shutupmac-cli --clear-single
shutupmac-cli --clear-stack
shutupmac-cli --list-visible
shutupmac-cli --ax-dump
```

Common aliases:

```sh
shutupmac-cli -a   # clear all
shutupmac-cli -v   # clear visible
shutupmac-cli -n   # clear single/top visible notification
shutupmac-cli -s   # clear top visible stack
shutupmac-cli -l   # list visible notification candidates
```

Diagnostic options:

```sh
shutupmac-cli --debug
shutupmac-cli --ax-dump
shutupmac-cli --ax-dump --probe-menus
```

`--ax-dump` and `--probe-menus` are developer diagnostics and are not intended as normal user-facing features.

## Accessibility permission

ShutUpMac needs macOS Accessibility permission to inspect and press Notification Center controls.

To enable it:

1. Open **System Settings**
2. Go to **Privacy & Security**
3. Open **Accessibility**
4. Enable ShutUpMac

If permission is missing, ShutUpMac will prompt macOS to show the Accessibility permission flow.

## Project layout

The core notification engine is split into focused files:

```text
ShutUpMacEngine.swift
  Shared config, debug utilities, result type, and public wrappers

AXHelpers.swift
  Generic Accessibility helper functions

NotificationCenterAccess.swift
  Finding, opening, and closing Notification Center

NotificationClearAll.swift
  Robust clear-all behavior

VisibleNotifications.swift
  Visible notification and visible stack discovery/actions

AXDiagnostics.swift
  Developer AX dump and menu probing diagnostics
```

GUI and app support files include:

```text
ShutUpMacApp.swift
  Menu bar app entry point and menu actions

SettingsView.swift
  App preferences, hotkey settings, launch-at-login, and CLI install command

AppPreferences.swift
  UserDefaults preference keys and defaults

HotKey.swift
  Hotkey model, encoding, decoding, display, and availability checks

HotKeyController.swift
  Global hotkey registration and dispatch

NotificationClearer.swift
  GUI-facing wrapper around engine actions and Accessibility permission checks
```

## Building

Open the Xcode project and build the app scheme:

```text
Scheme: ShutUpMac
Destination: My Mac
```

The CLI helper has its own scheme:

```text
Scheme: ShutUpMacCLI
Destination: My Mac
```

When changing shared engine files, build both schemes.

## Development notes

The app and CLI share the same notification engine. The GUI should generally expose only stable, user-friendly actions. More experimental or diagnostic actions should stay CLI-only until their behavior is polished.

Current product-facing actions:

- Clear Visible Notifications
- Clear All Notifications

CLI-only or advanced actions:

- Clear single/top visible notification
- Clear top visible stack
- AX dump
- Probe menus

## License

This project is licensed under the GNU General Public License version 2.0. See `LICENSE` for details.
