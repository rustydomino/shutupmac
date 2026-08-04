# ShutUpMac

ShutUpMac is a macOS menu bar utility for clearing, observing, and automating Notification Center notifications.

It combines keyboard- and command-driven notification dismissal with an embedded Notilog watcher, searchable notification history, and configurable privacy controls. It is built around macOS Accessibility automation.

GitHub page: https://github.com/rustydomino/shutupmac

## Features

### Menu bar app

- Clear most recent notification
- Clear desktop notifications
- Clear all notifications
- Send a test notification
- Configurable global hotkeys
- Native macOS Settings window with five toolbar tabs: General, Hot Keys, Activity, Rules, and Advanced
- Searchable Activity history backed by Notilog history and live monitoring
- Create an ordinary dismissal rule directly from a selected Activity record
- Rules tab for viewing, enabling, creating, editing, and deleting ordinary notification-dismissal rules
- Finder-style ascending/descending rule-name sorting with alternating row backgrounds
- Exact or contains matching for title, subtitle, and body, plus contains-based exceptions
- Optional notification logging with live enable/disable control
- Optional title, subtitle, and body redaction for Activity and persisted history
- Shared, validated retention limits stored in `retention.json`
- Database statistics, directly editable retention controls with native steppers and default reset, and Activity-database reset in the Advanced tab
- Atomic save-and-activate updates for `config.json` automation rules
- Optional launch at login
- Menu-bar-only operation without a Dock or app-switcher icon

### Notification clearing actions

| Action | What it does |
| --- | --- |
| Clear Most Recent Notification | Clears the top visible notification, or clears the top visible notification stack if the newest visible item is a stack. |
| Clear Desktop Notifications | Clears currently visible desktop notifications and visible stacks without opening Notification Center. |
| Clear All Notifications | Opens Notification Center if needed and clears all available notifications. |
| Send Test Notification | Sends a test notification so you can verify notification-clearing behavior. |

### Default global hotkeys

| Action | Default shortcut |
| --- | --- |
| Clear Most Recent Notification | `Control` + `Option` + `Command` + `R` |
| Clear Desktop Notifications | `Control` + `Option` + `Command` + `D` |
| Clear All Notifications | `Control` + `Option` + `Command` + `A` |
| Send Test Notification | `Control` + `Option` + `Command` + `T` |

Hotkeys can be changed in Settings.


## Installation

1. Download `ShutUpMac-0.6.0-macOS.zip` from the GitHub release.
2. Extract the ZIP.
3. Move `ShutUpMac.app` to `/Applications`.
4. Install the supplied default configuration files:

   ```sh
   mkdir -p "$HOME/Library/Application Support/notilog"

   cp Defaults/config.json \
     "$HOME/Library/Application Support/notilog/config.json"

   cp Defaults/retention.json \
     "$HOME/Library/Application Support/notilog/retention.json"
   ```

   Do not overwrite existing files unless you intend to replace your
   current rules and retention settings.

5. Open ShutUpMac.

### Opening the unsigned release

ShutUpMac 0.6.0 is ad hoc signed but is not notarized with Apple. macOS
may initially prevent it from opening.

After attempting to open the app:

1. Open **System Settings → Privacy & Security**.
2. Scroll to the Security section.
3. Click **Open Anyway** for ShutUpMac.
4. Confirm by clicking **Open**.

Only bypass this warning for a copy downloaded from the official
ShutUpMac GitHub release. The release includes a SHA-256 checksum that
can be used to verify the downloaded ZIP.

### First-launch permission

ShutUpMac requires Accessibility permission to inspect and dismiss
notifications.

When prompted, enable ShutUpMac under:

**System Settings → Privacy & Security → Accessibility**

After permission is granted, return to ShutUpMac. Monitoring should
begin without requiring the app to restart.

---

## Replacement Accessibility paragraph

Replace the existing paragraph:

> If permission is missing, ShutUpMac will prompt macOS to show the Accessibility permission flow.

with:

If permission is missing, ShutUpMac prompts macOS to show the
Accessibility permission flow. After permission is granted, return to
ShutUpMac; the app rechecks permission and starts monitoring without
requiring a restart.

## Notification activity and privacy

ShutUpMac starts the reusable `NotilogCore` monitoring pipeline inside the app when Accessibility permission and the Notilog configuration are available. The app uses the legacy Notilog runtime directory:

```text
~/Library/Application Support/notilog/
```

The **Activity** tab loads up to 1,000 recent notification appearance records from SQLite and then appends newly observed notifications while ShutUpMac is running. The table includes the source app, notification preview, matched rules, and appearance time, with full-text search and sortable columns. A selected record can seed a new ordinary dismissal rule without saving it automatically.

The **General** tab includes **Enable notification logging**:

- Enabled: new notifications are written to SQLite and published to Activity.
- Disabled: scanning, rule matching, actions, and delayed verification continue, but new notification records are not written or added to Activity. Existing history remains available through a read-only database connection. Opening that history does not migrate the schema, apply retention pruning, or create a missing database.

**Redact notification contents** is a suboption of notification logging. Title, subtitle, and body can be selected independently. Selected nonempty fields are replaced with `[REDACTED]` before they are written to SQLite or shown in Activity. The source application remains visible in the GUI. Policy changes apply to subsequent records immediately; previously stored rows are not rewritten.

The redaction controls retain their saved selections when logging is disabled. At least one content field must remain selected while redaction is enabled.

### Retention and database management

The **Advanced** tab shows Activity-event, action-run, session, date-range, and database-size statistics. It also provides validated retention controls and a confirmed Activity-database reset operation.

Retention settings are shared by the GUI and `notilog-cli` through:

```text
~/Library/Application Support/notilog/retention.json
```

Built-in defaults are 25,000 notification events and 10,000 action runs. Supported ranges are 1,000–100,000 events and 1,000–50,000 action runs. GUI values can be typed directly or adjusted in 1,000-record steps. **Reset to Default** prepares the built-in values, but no change is saved or pruned until **Apply Retention Limits** is pressed. Lowering a limit immediately prunes the oldest excess historical rows; increasing a limit affects future retention. A missing file uses the built-in defaults without creating the file merely to read them.

## Notification rules

The **Rules** tab provides a deliberately small GUI for ordinary notification-dismissal rules. An ordinary GUI rule:

- Matches notification appearance events only.
- Performs one plain `shutupmac_dismiss` action.
- Supports exact application matching.
- Supports exact or contains matching for title, subtitle, and body.
- Combines positive match fields with AND and ignores empty fields.
- Requires at least one positive match field.
- Supports title, subtitle, and body exceptions using contains matching.
- Combines exception rows with OR; any matching exception prevents dismissal.
- Applies one rule-level case-sensitivity setting to matches and exceptions.

The Rules tab can enable or disable, add, edit, and delete ordinary rules. Its Rule Name header toggles Finder-style ascending and descending display order without rewriting the stored configuration order. Editing preserves the rule UUID and stored position. Rules using advanced event matching, advanced field combinations, or advanced actions remain visible but read-only so the GUI does not silently discard configuration it does not understand.

Inside the ShutUpMac app, matching dismissal rules call the existing Accessibility dismissal engine directly through a host-injected callback. The app does not launch `shutupmac-cli` for these actions. The standalone `notilog-cli` retains the external-helper fallback when no in-process handler is supplied.

macOS may expose multiple notifications from one application as a single collapsed Accessibility stack. When a matching notification is represented by such a stack, the available AX action can clear the entire stack, including older nonmatching notifications from the same application. ShutUpMac records notification activity when logging is enabled, but the Accessibility API does not currently provide a dependable way to target one collapsed child notification.

## Command line helper

The repository also builds an imperative dismissal helper named:

```sh
shutupmac-cli
```

Supported CLI actions include:

```sh
shutupmac-cli --clear-all
shutupmac-cli --clear-desktop
shutupmac-cli --clear-single
shutupmac-cli --clear-stack
shutupmac-cli --dismiss-key "AXNotificationCenterAlert|D52E0071-45AD-440A-AEE3-40DF7D88CDC7"
shutupmac-cli --list-visible
shutupmac-cli --version
shutupmac-cli --ax-dump
```

Common aliases:

```sh
shutupmac-cli -a   # clear all
shutupmac-cli -d   # clear desktop notifications
shutupmac-cli -n   # clear single/top visible notification
shutupmac-cli -s   # clear top visible stack
shutupmac-cli -l   # list visible notification candidates
shutupmac-cli -v   # print version
```

Targeted automation:

```sh
shutupmac-cli --dismiss-key "AXNotificationCenterAlert|D52E0071-45AD-440A-AEE3-40DF7D88CDC7"
```

`--dismiss-key` dismisses one currently visible notification or notification stack by runtime Accessibility key.

Key format:

```text
<AXSubrole>|<AXIdentifier>
```

Example:

```text
AXNotificationCenterAlert|D52E0071-45AD-440A-AEE3-40DF7D88CDC7
```

This key is not a permanent Apple notification database ID. It identifies a currently visible Accessibility element, so it is intended for immediate automation by tools that observe visible notifications and then ask ShutUpMac to dismiss the matching element.

You can inspect currently visible notification keys with:

```sh
shutupmac-cli --list-visible
```

Legacy aliases:

```sh
shutupmac-cli --clear-visible                 # same as --clear-desktop
shutupmac-cli --dismiss-notification-key KEY  # same as --dismiss-key
```

Diagnostic options:

```sh
shutupmac-cli --debug
shutupmac-cli --ax-dump
shutupmac-cli --ax-dump --probe-menus
```

`--ax-dump` and `--probe-menus` are developer diagnostics and are not intended as normal user-facing features.


## Notilog command-line host

`notilog-cli` is separate from `shutupmac-cli`. `shutupmac-cli` performs immediate Notification Center dismissal commands; `notilog-cli` watches notifications, records Activity history, evaluates automation rules, and manages Notilog configuration.

Common commands:

```sh
notilog-cli permissions
notilog-cli watch
notilog-cli watch --no-logging --run-actions
notilog-cli history --limit 20
notilog-cli action-history --limit 20
notilog-cli rules
notilog-cli config-check
notilog-cli retention show
notilog-cli retention set --events 25000 --actions 10000
notilog-cli retention reset
```

`history` and `action-history` open the database read-only. They do not create a missing database, migrate its schema, or apply retention pruning. CLI `watch --no-logging` is stricter than the GUI logging-disabled mode: it never opens SQLite, while the app may keep an existing database open read-only so prior Activity remains visible. See [`Packages/notilog/README.md`](Packages/notilog/README.md) for configuration, privacy modes, and automation examples.

## Accessibility permission

ShutUpMac needs macOS Accessibility permission to inspect and press Notification Center controls.

To enable it:

1. Open **System Settings**
2. Go to **Privacy & Security**
3. Open **Accessibility**
4. Enable ShutUpMac

If permission is missing, ShutUpMac will prompt macOS to show the Accessibility permission flow.

## Notification permission

ShutUpMac can send a test notification from the menu bar app. Test notifications require macOS notification permission.

If test notifications are disabled, open ShutUpMac notification settings from the app prompt or manually in System Settings.

For persistent test notifications, set ShutUpMac's notification style to **Alerts** in System Settings. macOS controls this setting; ShutUpMac cannot force alert-style notifications automatically.

## Menu-bar-only behavior

ShutUpMac runs as a menu-bar-only utility. It does not present a Dock icon or remain in the Command-Tab app switcher. **Settings…** opens the native five-tab Settings window, while About remains a separate small window.

## Project layout

The repository contains the ShutUpMac application and the Notilog notification-monitoring and automation engine:

```text
ShutUpMac/
├── Sources/ShutUpMac/
│   ├── ShutUpMac.xcodeproj
│   ├── ShutUpMac/
│   └── ShutUpMacCLI/
└── Packages/notilog/
    ├── Package.swift
    ├── Sources/
    │   ├── NotilogCore/
    │   └── notilog-cli/
    └── Tests/NotilogCoreTests/
```

`NotilogCore` is included as a local Swift package dependency of the ShutUpMac app target. It provides reusable notification scanning, lifecycle tracking, rule matching, action coordination, SQLite persistence, and privacy/output policy behavior.

The `notilog-cli` executable remains available for development, diagnostics, scripting, and direct testing.

The ShutUpMac app hosts the Notilog watcher directly. It owns the polling lifecycle, loads historical notification records, publishes live activity, activates automation rules from `config.json`, reads shared retention from `retention.json`, can change logging and redaction policy without restarting monitoring, and injects the in-process notification dismissal handler used by runtime automation. The standalone `notilog-cli` remains available for diagnostics, scripting, and direct testing.

### ShutUpMac dismissal engine

The core notification dismissal engine is split into focused files:

```text
ShutUpMacEngine.swift
  Shared config, debug utilities, result types, notification AX key model,
  and public wrappers

AXHelpers.swift
  Generic Accessibility helper functions

NotificationCenterAccess.swift
  Finding, opening, and closing Notification Center

NotificationClearAll.swift
  Robust clear-all behavior

VisibleNotifications.swift
  Visible notification and visible stack discovery/actions, including
  targeted dismissal by runtime Accessibility key

AXDiagnostics.swift
  Developer AX dump and menu probing diagnostics
```

GUI and app support files include:

```text
ShutUpMacApp.swift
  Menu bar app entry point and menu actions

ShutUpMacManagementView.swift / ShutUpMacNavigation.swift
  Unified five-tab management window, destination routing, and Activity-to-Rules drafts

SettingsView.swift / HotKeySettingsView.swift
  General preferences, logging/redaction controls, launch-at-login, and hotkeys

ActivityView.swift / ActivityStore.swift
  Searchable, sortable notification history and live Activity presentation

RulesView.swift
  Ordinary-rule viewer/editor, advanced-rule classification, validation,
  exceptions, enable/disable controls, and read-only advanced-rule details

AutomationConfigurationStore.swift
  Atomic configuration persistence and runtime activation

NotilogMonitoringController.swift / NotilogMonitoringRuntime.swift
  App-owned Notilog lifecycle, one-cycle processing, read-only history access,
  automation activation, persistence control, retention updates, typed error
  presentation, live privacy-policy updates, and host-injected dismissal

AdvancedView.swift
  Database statistics, shared retention settings, and Activity database reset

AppPreferences.swift
  UserDefaults preferences, redaction-policy construction, and one-time migration
  of legacy retention values into the shared retention file

HotKey.swift
  Hotkey model, encoding, decoding, display, and availability checks

HotKeyController.swift
  Global hotkey registration and dispatch

MenuKeyboardShortcut.swift
  Dynamic menu shortcut display for configurable hotkeys

NotificationClearer.swift
  GUI-facing wrapper around engine actions and Accessibility permission checks

TestNotificationSender.swift
  Test notification scheduling and notification-click handling
```

### Notilog package

The local Swift package contains two products:

```text
NotilogCore
  Reusable notification observation, event tracking, rule evaluation,
  action execution, persistence, and privacy/output policy code

notilog-cli
  Command-line client for watching notifications, inspecting history,
  validating rules, running automation, and diagnostics
```

Notilog tests are located in:

```text
Packages/notilog/Tests/NotilogCoreTests/
```

## Building

### ShutUpMac app

Open the Xcode project and build the app scheme:

```text
Project: Sources/ShutUpMac/ShutUpMac.xcodeproj
Scheme: ShutUpMac
Destination: My Mac
```

The app target links the local `NotilogCore` package product and starts the embedded watcher at runtime after Accessibility permission and configuration validation succeed.

### ShutUpMac CLI

The CLI helper has its own scheme:

```text
Project: Sources/ShutUpMac/ShutUpMac.xcodeproj
Scheme: ShutUpMacCLI
Destination: My Mac
```

When changing shared ShutUpMac engine files, build both Xcode schemes.

### Notilog package and CLI

From the repository root, build the Notilog package with:

```zsh
swift build --package-path Packages/notilog
```

Run its tests with:

```zsh
swift test --package-path Packages/notilog
```

Run the CLI through Swift Package Manager with:

```zsh
swift run --package-path Packages/notilog notilog-cli --version
```

Changes to `NotilogCore` should be checked with both `swift test` and an Xcode build of the ShutUpMac app target.

## Development notes

The app and `shutupmac-cli` share the same notification dismissal engine. The GUI should generally expose only stable, user-friendly actions. More experimental or diagnostic actions should stay CLI-only until their behavior is polished.

Current product-facing actions:

- Clear Most Recent Notification
- Clear Desktop Notifications
- Clear All Notifications
- Send Test Notification

CLI-only or advanced actions:

- Clear single/top visible notification
- Clear top visible stack
- Dismiss by runtime Accessibility key
- List visible notification candidates
- AX dump
- Probe menus

`--dismiss-key` remains a supported automation and diagnostic integration point for external tools and the standalone Notilog host. The embedded ShutUpMac runtime now avoids the helper subprocess and calls the same dismissal engine through an injected in-process handler.

Notilog remains independently usable through `notilog-cli` and is also the active monitoring and automation subsystem embedded in the ShutUpMac app. Preserve the host/core boundary and avoid duplicating notification scanning, persistence, rule matching, privacy policy, or dismissal logic across app and CLI targets.

## Version history

See `CHANGELOG.md`.

## License

This project is licensed under the GNU General Public License version 2.0. See `LICENSE` for details.
