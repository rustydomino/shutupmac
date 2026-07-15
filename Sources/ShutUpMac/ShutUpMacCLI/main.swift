import Foundation
import Darwin

// Add this file only to the CLI target, not to the SwiftUI menu-bar app target.

private enum CLIAction: Equatable {
    case clearAll
    case clearDesktop
    case clearSingleNotification
    case clearTopVisibleStack
    case listVisible
    case axDump
    case version
    case help
}

private struct CLIOptions {
    var action: CLIAction = .clearAll
    var didSetAction = false
    var quiet = false
    var debug = false
    var probeMenus = false
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

case .version:
    print(appVersionString())
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

case .axDump:
    ShutUpMac.dumpNotificationCenterAXControls(probeMenus: options.probeMenus)
    Darwin.exit(0)

case .clearAll:
    finish(with: ShutUpMac.clearNotifications(), quiet: options.quiet)

case .clearDesktop:
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

        case "--version", "-v":
            if let error = setAction(.version, from: arg) { return (nil, error) }

        case "--clear-all", "-a":
            if let error = setAction(.clearAll, from: arg) { return (nil, error) }

        case "--clear-desktop", "-d":
            if let error = setAction(.clearDesktop, from: arg) { return (nil, error) }

        case "--clear-visible":
            // Legacy alias. Prefer --clear-desktop / -d.
            if let error = setAction(.clearDesktop, from: arg) { return (nil, error) }

        case "--clear-single", "-n":
            if let error = setAction(.clearSingleNotification, from: arg) { return (nil, error) }

        case "--clear-stack", "-s":
            if let error = setAction(.clearTopVisibleStack, from: arg) { return (nil, error) }

        case "--list", "--list-visible", "-l":
            if let error = setAction(.listVisible, from: arg) { return (nil, error) }

        case "--ax-dump":
            if let error = setAction(.axDump, from: arg) { return (nil, error) }

        case "--probe-menus":
            options.probeMenus = true

        case "--debug":
            options.debug = true

        case "--quiet", "-q":
            options.quiet = true

        default:
            return (nil, "Unknown argument: \(arg)")
        }
    }

    if options.probeMenus && options.action != .axDump {
        return (nil, "--probe-menus can only be used with --ax-dump")
    }

    if options.quiet && options.action == .axDump {
        return (nil, "--quiet cannot be used with --ax-dump")
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

private func appVersionString() -> String {
    guard let info = appInfoDictionary() else {
        return "ShutUpMac version unknown"
    }

    let version = info["CFBundleShortVersionString"] as? String
    let build = info["CFBundleVersion"] as? String

    switch (version, build) {
    case let (.some(version), .some(build)):
        return "ShutUpMac \(version) (\(build))"

    case let (.some(version), .none):
        return "ShutUpMac \(version)"

    case let (.none, .some(build)):
        return "ShutUpMac build \(build)"

    case (.none, .none):
        return "ShutUpMac version unknown"
    }
}

private func appInfoDictionary() -> [String: Any]? {
    containingAppInfoDictionary() ?? Bundle.main.infoDictionary
}

private func containingAppInfoDictionary() -> [String: Any]? {
    guard let executablePath = executablePath() else {
        return nil
    }

    var currentURL = URL(fileURLWithPath: executablePath)
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()

    for _ in 0..<8 {
        let infoURL = currentURL.appendingPathComponent("Info.plist")

        if FileManager.default.fileExists(atPath: infoURL.path),
           let dictionary = propertyListDictionary(at: infoURL) {
            return dictionary
        }

        currentURL.deleteLastPathComponent()
    }

    return nil
}

private func propertyListDictionary(at url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url),
          let object = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
          ),
          let dictionary = object as? [String: Any]
    else {
        return nil
    }

    return dictionary
}

private func executablePath() -> String? {
    var size: UInt32 = 0

    _ = _NSGetExecutablePath(nil, &size)

    var buffer = [CChar](repeating: 0, count: Int(size))

    guard _NSGetExecutablePath(&buffer, &size) == 0 else {
        return nil
    }

    return String(cString: buffer)
}

private func usage() -> String {
    """
    Usage:
      shutupmac-cli [action] [options]

    Actions:
      --clear-all, -a
          Reliable clear-all method. Opens Notification Center,
          presses Clear All Notifications, then closes Notification Center.
          This is also the default when no action is provided.

      --clear-desktop, -d
          Clear desktop notifications without opening Notification Center.
          Repeatedly clears visible single notifications and visible stacks
          until no actionable desktop notification items remain.

      --clear-single, -n
          Clear the top visible single notification only.
          Ignores notification stacks.

      --clear-stack, -s
          Clear the top visible notification stack only.
          Ignores single notifications.

      --list, --list-visible, -l
          Print visible notification and stack candidates for testing.
          Does not perform an action.

      --ax-dump
          Print suspicious Notification Center Accessibility elements for
          reverse-engineering and diagnostics. Does not clear notifications.

      --version, -v
          Print the ShutUpMac app version and exit.

    Options:
      --probe-menus
          With --ax-dump only, actively perform AXShowMenu on suspicious
          elements and print the relevant menu-ish items that appear.
          This may perturb Notification Center state.

      --debug
          Enable concise operational debug logging in release builds.

      --quiet, -q
          Suppress successful status output. Not valid with --ax-dump.

      --help, -h
          Show this help text.

    Legacy aliases:
      --clear-visible
          Same as --clear-desktop. Prefer --clear-desktop or -d.

    Examples:
      shutupmac-cli
      shutupmac-cli --version
      shutupmac-cli -v
      shutupmac-cli --clear-all --debug
      shutupmac-cli --clear-desktop --debug
      shutupmac-cli -d
      shutupmac-cli --clear-single
      shutupmac-cli --clear-stack
      shutupmac-cli --list
      shutupmac-cli --ax-dump
      shutupmac-cli --ax-dump --probe-menus
    """
}
