import Foundation
import ApplicationServices

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
