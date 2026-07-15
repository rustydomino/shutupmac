import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

private enum MuteConfig {
    static let menuSearchTimeout: TimeInterval = 0.1
    static let menuSearchInterval: TimeInterval = 0.015
    static let postMuteDelay: TimeInterval = 0.05

    static let sourceDisappearTimeout: TimeInterval = 0.45
    static let sourceDisappearPollingInterval: TimeInterval = 0.03

    static let muteForTodayTitle = "Mute for Today"
}

private let axChildAttributeNames = [
    kAXVisibleChildrenAttribute as String,
    kAXChildrenAttribute as String,
    "AXChildrenInNavigationOrder"
]

extension ShutUpMac {
    static func muteVisibleNotificationsForTodayResult() -> ClearNotificationsResult {
        debugLog("AX trusted: \(AXIsProcessTrusted())")

        let visibleItems = visibleNotificationItems()

        guard let item = topVisibleNotificationItem(from: visibleItems) else {
            return .success(
                "Nothing to mute: no visible notifications found",
                didClear: false
            )
        }

        let sourceName = visibleNotificationSourceName(item) ?? "unknown source"

        debugLog(
            "MUTE_TOP: source=\(sourceName) " +
            "candidate kind=\(item.kindLabel) frame=\(formatFrame(item.frame)) \(compactDescribe(item.element))"
        )

        guard performMuteForToday(on: item) else {
            return .success(
                "Nothing muted: top visible notification source did not expose Mute for Today",
                didClear: false
            )
        }

        debugLog("MUTE_TOP: pressed Mute for Today for source: \(sourceName)")

        return .success(
            "SUCCESS: pressed Mute for Today for top visible notification source: \(sourceName)",
            didClear: true
        )
    }
}
private func topVisibleNotificationItem(
    from items: [VisibleNotificationItem]
) -> VisibleNotificationItem? {
    items.sorted { lhs, rhs in
        if lhs.frame.origin.y == rhs.frame.origin.y {
            return lhs.frame.origin.x < rhs.frame.origin.x
        }

        // macOS screen coordinates: lower y is closer to the top.
        return lhs.frame.origin.y < rhs.frame.origin.y
    }
    .first
}

private func visibleNotificationSourceName(_ item: VisibleNotificationItem) -> String? {
    let desc = strAttr(item.element, kAXDescriptionAttribute) ?? ""

    guard let firstPart = desc.split(separator: ",", maxSplits: 1).first else {
        return nil
    }

    let sourceName = firstPart.trimmingCharacters(in: .whitespacesAndNewlines)

    return sourceName.isEmpty ? nil : sourceName
}

private func visibleNotificationSourceKey(_ item: VisibleNotificationItem) -> String {
    if let sourceName = visibleNotificationSourceName(item) {
        return "source:\(sourceName.lowercased())"
    }

    return "item:\(visibleNotificationStableKey(item))"
}

private func waitForSourceToDisappear(sourceKey: String) -> Bool {
    let deadline = Date().addingTimeInterval(MuteConfig.sourceDisappearTimeout)

    while Date() < deadline {
        let stillVisible = visibleNotificationItems().contains { item in
            visibleNotificationSourceKey(item) == sourceKey
        }

        if !stillVisible {
            return true
        }

        Thread.sleep(forTimeInterval: MuteConfig.sourceDisappearPollingInterval)
    }

    return false
}

private func performMuteForToday(on item: VisibleNotificationItem) -> Bool {
    debugLog("MUTE_TOP: trying coordinate-free AXShowMenu path")

    if pressMuteForTodayUsingAXShowMenu(near: item) {
        return true
    }

    debugLog("MUTE_TOP: Mute for Today not found using AXShowMenu path")
    debugDumpMuteMenuCandidates()

    return false
}

private func pressMuteForTodayUsingAXShowMenu(near item: VisibleNotificationItem) -> Bool {
    let candidates = axShowMenuCandidates(near: item)

    debugLog("MUTE_TOP: AXShowMenu candidate count=\(candidates.count)")

    for (index, candidate) in candidates.enumerated() {
        debugLog("MUTE_TOP: AXShowMenu attempt \(index + 1)/\(candidates.count)")
        debugLog("MUTE_TOP: AXShowMenu candidate \(compactDescribe(candidate))")

        let result = AXUIElementPerformAction(
            candidate,
            kAXShowMenuAction as CFString
        )

        debugLog("MUTE_TOP: AXShowMenu result: \(result.rawValue) \(result)")

        // Do not require result == .success.
        // Testing showed a non-success return can still expose the correct menu.
        if pressMuteForTodayMenuItemIfPresent() {
            return true
        }

        debugLog("MUTE_TOP: no Mute for Today after AXShowMenu attempt \(index + 1)")
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

    for name in axChildAttributeNames {
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
    let start = Date()

    guard let menuItem = waitForMuteForTodayMenuItem() else {
        debugLog("MUTE_TOP: no Mute for Today menu item found after \(Date().timeIntervalSince(start))s")
        return false
    }

    debugLog("MUTE_TOP: found Mute for Today menu item after \(Date().timeIntervalSince(start))s \(compactDescribe(menuItem))")

    let pressStart = Date()
    let didPress = press(menuItem)
    debugLog("MUTE_TOP: press Mute for Today completed after \(Date().timeIntervalSince(pressStart))s")

    return didPress
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

        for root in focusedMenuSearchRoots(for: axApp) {
            if let menuItem = findMuteForTodayMenuItemFast(in: root) {
                return menuItem
            }
        }

        if let menuItem = findMuteForTodayMenuItemFast(in: axApp) {
            return menuItem
        }
    }

    return nil
}

private func focusedMenuSearchRoots(for axApp: AXUIElement) -> [AXUIElement] {
    var roots: [AXUIElement] = []

    if let focusedElement = axElementAttribute(axApp, kAXFocusedUIElementAttribute as String) {
        roots.append(focusedElement)
        roots.append(contentsOf: axAncestors(of: focusedElement, limit: 4))
    }

    if let focusedWindow = axElementAttribute(axApp, kAXFocusedWindowAttribute as String) {
        roots.append(focusedWindow)
    }

    return uniqueAXElements(roots)
}

private func findMuteForTodayMenuItemFast(in root: AXUIElement) -> AXUIElement? {
    var visited = Set<CFHashCode>()
    var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
    var scannedNodeCount = 0

    let maxDepth = 8
    let maxNodes = 250

    while !queue.isEmpty {
        let current = queue.removeFirst()
        let element = current.element
        let depth = current.depth

        let hash = CFHash(element)

        guard !visited.contains(hash) else {
            continue
        }

        visited.insert(hash)
        scannedNodeCount += 1

        if scannedNodeCount > maxNodes {
            debugLog("MUTE_TOP: fast menu search stopped at maxNodes=\(maxNodes)")
            return nil
        }

        let role = strAttr(element, kAXRoleAttribute) ?? ""

        // Do not wander into the normal macOS menu bar. Earlier dumps showed
        // Apple menu / Recent Items noise here, which is not the context menu.
        if role == "AXMenuBar" || role == "AXMenuBarItem" {
            continue
        }

        if isVisibleMuteForTodayMenuItem(element, role: role) {
            debugLog("MUTE_TOP: fast menu search scanned \(scannedNodeCount) node(s)")
            return element
        }

        guard depth < maxDepth else {
            continue
        }

        guard shouldDescendDuringMenuSearch(element, role: role, depth: depth) else {
            continue
        }

        for name in axChildAttributeNames {
            for child in children(element, name) {
                queue.append((child, depth + 1))
            }
        }
    }

    debugLog("MUTE_TOP: fast menu search scanned \(scannedNodeCount) node(s), no match")
    return nil
}

private func isVisibleMuteForTodayMenuItem(
    _ element: AXUIElement,
    role: String
) -> Bool {
    let isMenuItem =
        role == "AXMenuItem" ||
        role.localizedCaseInsensitiveContains("menu")

    guard isMenuItem else {
        return false
    }

    guard let frame = frameAttr(element),
          frame.width > 0,
          frame.height > 0
    else {
        return false
    }

    let title = strAttr(element, kAXTitleAttribute) ?? ""
    let desc = strAttr(element, kAXDescriptionAttribute) ?? ""
    let enabled = boolAttr(element, kAXEnabledAttribute)

    guard enabled != false else {
        return false
    }

    let text = "\(title) \(desc)"

    return text.localizedCaseInsensitiveContains(MuteConfig.muteForTodayTitle)
}

private func shouldDescendDuringMenuSearch(
    _ element: AXUIElement,
    role: String,
    depth: Int
) -> Bool {
    if depth <= 2 {
        return true
    }

    if role.localizedCaseInsensitiveContains("menu") {
        return true
    }

    if role == "AXApplication" ||
        role == "AXWindow" ||
        role == "AXGroup" {
        return depth <= 4
    }

    return false
}

private func axElementAttribute(
    _ element: AXUIElement,
    _ name: String
) -> AXUIElement? {
    var value: CFTypeRef?

    let result = AXUIElementCopyAttributeValue(
        element,
        name as CFString,
        &value
    )

    guard result == .success,
          let value
    else {
        return nil
    }

    return unsafeBitCast(value, to: AXUIElement.self)
}

private func axAncestors(
    of element: AXUIElement,
    limit: Int
) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var current = axParent(of: element)
    var visited = Set<CFHashCode>()

    while let item = current, result.count < limit {
        let hash = CFHash(item)

        guard !visited.contains(hash) else {
            break
        }

        visited.insert(hash)
        result.append(item)

        current = axParent(of: item)
    }

    return result
}

private func uniqueAXElements(_ elements: [AXUIElement]) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var seen = Set<CFHashCode>()

    for element in elements {
        let hash = CFHash(element)

        guard !seen.contains(hash) else {
            continue
        }

        seen.insert(hash)
        result.append(element)
    }

    return result
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
            debugLog("MUTE_TOP: no menu-ish debug candidates for pid=\(app.processIdentifier)")
            continue
        }

        debugLog("MUTE_TOP: menu-ish debug candidates for pid=\(app.processIdentifier)")

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

    for name in axChildAttributeNames {
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
