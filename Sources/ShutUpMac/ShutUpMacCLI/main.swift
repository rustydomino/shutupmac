import Foundation
import Darwin

// Add this file only to the CLI target, not to the SwiftUI menu-bar app target.

private enum CLIAction {
    case clearAll
    case clearVisible
    case clearSingleNotification
    case clearTopVisibleStack
    case listVisible
    case help
}

private struct CLIOptions {
    var action: CLIAction = .clearAll
    var didSetAction = false
    var quiet = false
    var debug = false
}

private let parseResult = parse(arguments: Array(CommandLine.arguments.dropFirst()))

if let error = parseResult.error {
    fputs(error + "\n\n", stderr)
    fputs(usage(), stderr)
    Darwin.exit(2)
}

private let options = parseResult.options ?? CLIOptions()

if options.debug {
    Debug.isEnabled = true
}

switch options.action {
case .help:
    print(usage())
    Darwin.exit(0)

case .listVisible:
    let lines = ShutUpMac.visibleNotificationSummaries()
    if lines.isEmpty {
        if !options.quiet {
            print("No visible notification candidates found")
        }
    } else {
        for line in lines {
            print(line)
        }
    }
    Darwin.exit(0)

case .clearAll:
    finish(with: ShutUpMac.clearNotifications(), quiet: options.quiet)

case .clearVisible:
    finish(with: ShutUpMac.clearVisibleNotificationsResult(), quiet: options.quiet)

case .clearSingleNotification:
    finish(with: ShutUpMac.closeTopVisibleNotificationResult(), quiet: options.quiet)

case .clearTopVisibleStack:
    finish(with: ShutUpMac.clearTopVisibleStackResult(), quiet: options.quiet)
}

private func parse(arguments: [String]) -> (options: CLIOptions?, error: String?) {
    var options = CLIOptions()

    func setAction(_ action: CLIAction, from flag: String) -> String? {
        if options.didSetAction {
            return "Only one action flag can be used at a time. Extra flag: \(flag)"
        }

        options.action = action
        options.didSetAction = true
        return nil
    }

    for arg in arguments {
        switch arg {
        case "--help", "-h":
            if let error = setAction(.help, from: arg) { return (nil, error) }

        case "--clear-all", "-a":
            if let error = setAction(.clearAll, from: arg) { return (nil, error) }

        case "--clear-visible", "-v":
            if let error = setAction(.clearVisible, from: arg) { return (nil, error) }

        case "--clear-single", "-n":
            if let error = setAction(.clearSingleNotification, from: arg) { return (nil, error) }

        case "--clear-stack", "-s":
            if let error = setAction(.clearTopVisibleStack, from: arg) { return (nil, error) }

        case "--list", "--list-visible", "-l":
            if let error = setAction(.listVisible, from: arg) { return (nil, error) }

        case "--debug":
            options.debug = true

        case "--quiet", "-q":
            options.quiet = true

        default:
            return (nil, "Unknown argument: \(arg)")
        }
    }

    return (options, nil)
}

private func finish(with result: ClearNotificationsResult, quiet: Bool) -> Never {
    if !quiet || !result.succeeded {
        if result.succeeded {
            print(result.message)
        } else {
            fputs(result.message + "\n", stderr)
        }
    }

    Darwin.exit(result.exitCode)
}

private func usage() -> String {
    """
    Usage:
      shutupmac-cli [action] [options]

    Actions:
      --clear-all, -a
          Existing reliable clear-all method. Opens Notification Center,
          uses Clear All Notifications, then closes Notification Center.
          This is also the default when no action is provided.

      --clear-visible, -v
          Clear visible notifications only without opening Notification Center.
          Repeatedly clears visible single notifications and visible stacks
          until no actionable visible notification items remain.

      --clear-single, -n
          Clear the top visible single notification only.
          Ignores notification stacks.

      --clear-stack, -s
          Clear the top visible notification stack only.
          Ignores single notifications.

      --list, --list-visible, -l
          Print visible notification and stack candidates for testing.
          Does not perform an action.

    Options:
      --debug
          Enable debug logging in release builds.

      --quiet, -q
          Suppress successful status output.

      --help, -h
          Show this help text.

    Examples:
      shutupmac-cli
      shutupmac-cli --clear-all
      shutupmac-cli --clear-visible
      shutupmac-cli --clear-single
      shutupmac-cli --clear-stack
      shutupmac-cli --list --debug
    """
}
