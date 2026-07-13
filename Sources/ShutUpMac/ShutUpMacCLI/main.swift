import Foundation
import ApplicationServices

let arguments = CommandLine.arguments.dropFirst()

Debug.isEnabled = false

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    Usage:
      shutupmac-cli [--debug]

    Options:
      --debug     Print diagnostic Accessibility logs.
      -h, --help  Show this help text.
    """)
    exit(0)
}

if arguments.contains("--debug") {
    Debug.isEnabled = true
}

guard isAccessibilityTrusted(prompt: true) else {
    fputs("ShutUpMac needs Accessibility permission.\n", stderr)
    exit(1)
}

let result = ShutUpMac.clearNotifications()

if result.succeeded {
    print(result.message)
} else {
    fputs("\(result.message)\n", stderr)
}

exit(result.exitCode)

private func isAccessibilityTrusted(prompt: Bool) -> Bool {
    let options = [
        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
    ] as CFDictionary

    return AXIsProcessTrustedWithOptions(options)
}
