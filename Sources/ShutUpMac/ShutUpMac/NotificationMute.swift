import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

private enum MuteConfig {
    static let maxCycles = 50
    static let menuOpenDelay: TimeInterval = 0.15
    static let menuSearchTimeout: TimeInterval = 0.60
    static let menuSearchInterval: TimeInterval = 0.03
    static let postMuteDelay: TimeInterval = 0.30
    static let progressTimeout: TimeInterval = 0.60
    static let progressPollingInterval: TimeInterval = 0.03

    static let muteForTodayTitle = "Mute for Today"
}

extension ShutUpMac {
    static func muteVisibleNotificationsForTodayResult() -> ClearNotificationsResult {
        debugLog("AX trusted: \(AXIsProcessTrusted())")

        var didMuteAnything = false
        var muteActionCount = 0
        var attemptedKeys = Set<String>()

        for cycle in 1...MuteConfig.maxCycles {
            let visibleItems = visibleNotificationItems()
            let remainingCandidates = visibleItems.filter { item in
                !attemptedKeys.contains(visibleNotificationStableKey(item))
            }

            if remainingCandidates.isEmpty {
                if visibleItems.isEmpty {
                    if didMuteAnything {
                        let noun = muteActionCount == 1 ? "source" : "sources"

                        return .success(
                            "SUCCESS: muted \(muteActionCount) visible notification \(noun) for today",
                            didClear: true
                        )
                    }

                    return .success(
                        "Nothing to mute: no visible notifications found",
                        didClear: false
                    )
                }

                if didMuteAnything {
                    let noun = muteActionCount == 1 ? "source" : "sources"
                    let itemNoun = visibleItems.count == 1 ? "item remains" : "items remain"

                    return .success(
                        "PARTIAL: muted \(muteActionCount) visible notification \(noun) for today; \(visibleItems.count) visible \(itemNoun) without a usable Mute for Today action",
                        didClear: true
                    )
                }

                return .success(
                    "Nothing muted: no visible notification exposed Mute for Today",
                    didClear: false
                )
            }

            let item = remainingCandidates[0]
            let itemKey = visibleNotificationStableKey(item)

            debugLog("MUTE_VISIBLE: cycle=\(cycle) candidate kind=\(item.kindLabel) frame=\(formatFrame(item.frame)) \(compactDescribe(item.element))")

            let beforeItems = visibleNotificationItems()

            if performMuteForToday(on: item) {
                didMuteAnything = true
                muteActionCount += 1

                let observedProgress = waitForMuteProgress(
                    afterMuting: item,
                    previousItems: beforeItems
                )

                if observedProgress {
                    attemptedKeys.removeAll()
                } else {
                    attemptedKeys.insert(itemKey)
                }

                Thread.sleep(forTimeInterval: MuteConfig.postMuteDelay)
            } else {
                attemptedKeys.insert(itemKey)
            }
        }

        return .failure(
            "Stopped after \(MuteConfig.maxCycles) mute cycle(s); visible notifications may remain"
        )
    }
}

private func performMuteForToday(on item: VisibleNotificationItem) -> Bool {
    debugLog("MUTE_VISIBLE: trying coordinate-free AXShowMenu path")

    if pressMuteForTodayUsingAXShowMenu(near: item) {
        return true
    }

    debugLog("MUTE_VISIBLE: Mute for Today not found using AXShowMenu path")
    debugDumpMuteMenuCandidates()

    return false
}

private func pressMuteForTodayUsingAXShowMenu(near item: VisibleNotificationItem) -> Bool {
    let candidates = axShowMenuCandidates(near: item)

    debugLog("MUTE_VISIBLE: AXShowMenu candidate count=\(candidates.count)")

    for (index, candidate) in candidates.enumerated() {
        debugLog("MUTE_VISIBLE: AXShowMenu attempt \(index + 1)/\(candidates.count)")
        debugLog("MUTE_VISIBLE: AXShowMenu candidate \(compactDescribe(candidate))")

        let result = AXUIElementPerformAction(
            candidate,
            kAXShowMenuAction as CFString
        )

        debugLog("MUTE_VISIBLE: AXShowMenu result: \(result.rawValue) \(result)")

        Thread.sleep(forTimeInterval: MuteConfig.menuOpenDelay)

        // Do not require result == .success.
        // Testing showed a non-success return can still expose the correct menu.
        if pressMuteForTodayMenuItemIfPresent() {
            return true
        }

        debugLog("MUTE_VISIBLE: no Mute for Today after AXShowMenu attempt \(index + 1)")
        closeOpenContextMenu()
    }

    return false
}
private func axShowMenuCandidates(near item: VisibleNotificationItem) -> [AXUIElement] {
    var candidates: [AXUIElement] = []

    var descendantVisited = Set<CFHashCode>()
    collectAXShowMenuDescendants(
        item.element,
        visited: &descendantVisited,
        results: &candidates
    )

    candidates.append(item.element)
    candidates.append(contentsOf: axParents(of: item.element))

    return prioritizedUniqueAXShowMenuCandidates(candidates)
}

private func collectAXShowMenuDescendants(
    _ element: AXUIElement,
    depth: Int = 0,
    maxDepth: Int = 5,
    visited: inout Set<CFHashCode>,
    results: inout [AXUIElement]
) {
    guard depth <= maxDepth else {
        return
    }

    let hash = CFHash(element)

    guard !visited.contains(hash) else {
        return
    }

    visited.insert(hash)

    if actions(element).contains(kAXShowMenuAction as String) {
        results.append(element)
    }

    for name in [
        kAXVisibleChildrenAttribute,
        kAXChildrenAttribute,
        "AXChildrenInNavigationOrder"
    ] {
        for child in children(element, name) {
            collectAXShowMenuDescendants(
                child,
                depth: depth + 1,
                maxDepth: maxDepth,
                visited: &visited,
                results: &results
            )
        }
    }
}

private func axParents(of element: AXUIElement) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var current = axParent(of: element)
    var visited = Set<CFHashCode>()

    while let item = current {
        let hash = CFHash(item)

        guard !visited.contains(hash) else {
            break
        }

        visited.insert(hash)

        if actions(item).contains(kAXShowMenuAction as String) {
            result.append(item)
        }

        current = axParent(of: item)
    }

    return result
}

private func axParent(of element: AXUIElement) -> AXUIElement? {
    var value: CFTypeRef?

    let result = AXUIElementCopyAttributeValue(
        element,
        kAXParentAttribute as CFString,
        &value
    )

    guard result == .success,
          let value
    else {
        return nil
    }

    return unsafeBitCast(value, to: AXUIElement.self)
}

private func prioritizedUniqueAXShowMenuCandidates(_ candidates: [AXUIElement]) -> [AXUIElement] {
    var unique: [AXUIElement] = []
    var seen = Set<CFHashCode>()

    for candidate in candidates {
        let hash = CFHash(candidate)

        guard !seen.contains(hash) else {
            continue
        }

        seen.insert(hash)

        guard actions(candidate).contains(kAXShowMenuAction as String) else {
            continue
        }

        unique.append(candidate)
    }

    return unique.sorted { lhs, rhs in
        axShowMenuPriority(lhs) < axShowMenuPriority(rhs)
    }
}

private func axShowMenuPriority(_ element: AXUIElement) -> Int {
    let identifier = strAttr(element, kAXIdentifierAttribute) ?? ""
    let role = strAttr(element, kAXRoleAttribute) ?? ""

    if identifier == "title" {
        return 0
    }

    if identifier == "body" {
        return 1
    }

    if role == kAXStaticTextRole as String {
        return 2
    }

    return 10
}

private func pressMuteForTodayMenuItemIfPresent() -> Bool {
    guard let menuItem = waitForMuteForTodayMenuItem() else {
        debugLog("MUTE_VISIBLE: no Mute for Today menu item found")
        return false
    }

    debugLog("MUTE_VISIBLE: found Mute for Today menu item \(compactDescribe(menuItem))")

    return press(menuItem)
}

private func waitForMuteForTodayMenuItem() -> AXUIElement? {
    let deadline = Date().addingTimeInterval(MuteConfig.menuSearchTimeout)

    while Date() < deadline {
        if let menuItem = findMuteForTodayMenuItem() {
            return menuItem
        }

        Thread.sleep(forTimeInterval: MuteConfig.menuSearchInterval)
    }

    return nil
}

private func findMuteForTodayMenuItem() -> AXUIElement? {
    for app in notificationCenterApplications() {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        if let menuItem = findElement(
            axApp,
            maxDepth: Config.defaultAXTreeSearchMaxDepth,
            matches: isMuteForTodayMenuItem
        ) {
            return menuItem
        }
    }

    return nil
}

private func isMuteForTodayMenuItem(_ element: AXUIElement) -> Bool {
    let title = strAttr(element, kAXTitleAttribute) ?? ""
    let desc = strAttr(element, kAXDescriptionAttribute) ?? ""
    let role = strAttr(element, kAXRoleAttribute) ?? ""
    let enabled = boolAttr(element, kAXEnabledAttribute)

    let text = "\(title) \(desc)"

    guard text.localizedCaseInsensitiveContains(MuteConfig.muteForTodayTitle) else {
        return false
    }

    guard enabled != false else {
        return false
    }

    let roleLooksMenuLike =
        role.localizedCaseInsensitiveContains("menu") ||
        role.localizedCaseInsensitiveContains("button")

    let canPress = actions(element).contains(kAXPressAction as String)

    return roleLooksMenuLike || canPress
}

private func waitForMuteProgress(
    afterMuting targetItem: VisibleNotificationItem,
    previousItems: [VisibleNotificationItem]
) -> Bool {
    let targetKey = visibleNotificationStableKey(targetItem)
    let previousAllCount = previousItems.count
    let deadline = Date().addingTimeInterval(MuteConfig.progressTimeout)

    while Date() < deadline {
        let currentItems = visibleNotificationItems()
        let currentAllCount = currentItems.count
        let targetStillVisible = currentItems.contains { item in
            visibleNotificationStableKey(item) == targetKey
        }

        if !targetStillVisible || currentAllCount < previousAllCount {
            debugLog("MUTE_VISIBLE: observed progress targetStillVisible=\(targetStillVisible) all=\(previousAllCount)->\(currentAllCount)")
            return true
        }

        Thread.sleep(forTimeInterval: MuteConfig.progressPollingInterval)
    }

    debugLog("MUTE_VISIBLE: no observed progress after mute action")
    return false
}

private func closeOpenContextMenu() {
    guard let source = CGEventSource(stateID: .hidSystemState),
          let down = CGEvent(
            keyboardEventSource: source,
            virtualKey: 53,
            keyDown: true
          ),
          let up = CGEvent(
            keyboardEventSource: source,
            virtualKey: 53,
            keyDown: false
          )
    else {
        return
    }

    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)

    Thread.sleep(forTimeInterval: 0.10)
}

private func debugDumpMuteMenuCandidates() {
    guard Debug.isEnabled else {
        return
    }

    for app in notificationCenterApplications() {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var visited = Set<CFHashCode>()
        var candidates: [AXUIElement] = []

        collectMuteDebugCandidates(
            axApp,
            visited: &visited,
            candidates: &candidates
        )

        if candidates.isEmpty {
            debugLog("MUTE_VISIBLE: no menu-ish debug candidates for pid=\(app.processIdentifier)")
            continue
        }

        debugLog("MUTE_VISIBLE: menu-ish debug candidates for pid=\(app.processIdentifier)")

        for (index, candidate) in candidates.prefix(40).enumerated() {
            debugLog("  [\(index)] \(compactDescribe(candidate))")
        }

        if candidates.count > 40 {
            debugLog("  ... \(candidates.count - 40) additional candidate(s) omitted")
        }
    }
}

private func collectMuteDebugCandidates(
    _ element: AXUIElement,
    depth: Int = 0,
    maxDepth: Int = 12,
    visited: inout Set<CFHashCode>,
    candidates: inout [AXUIElement]
) {
    if depth > maxDepth {
        return
    }

    let hash = CFHash(element)

    if visited.contains(hash) {
        return
    }

    visited.insert(hash)

    let role = strAttr(element, kAXRoleAttribute) ?? ""
    let title = strAttr(element, kAXTitleAttribute) ?? ""
    let desc = strAttr(element, kAXDescriptionAttribute) ?? ""

    let text = "\(role) \(title) \(desc)".lowercased()

    if text.contains("mute") ||
        text.contains("today") ||
        text.contains("notification") ||
        text.contains("turn off") ||
        role.lowercased().contains("menu") {
        candidates.append(element)
    }

    for name in [
        kAXVisibleChildrenAttribute,
        kAXChildrenAttribute,
        "AXChildrenInNavigationOrder"
    ] {
        for child in children(element, name) {
            collectMuteDebugCandidates(
                child,
                depth: depth + 1,
                maxDepth: maxDepth,
                visited: &visited,
                candidates: &candidates
            )
        }
    }
}
