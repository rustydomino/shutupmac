import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - Visible Notification Discovery

enum VisibleNotificationKind: String, Hashable {
    case single
    case stack

    init?(subrole: String) {
        switch subrole {
        case Config.notificationAlertSubrole:
            self = .single
        case Config.notificationAlertStackSubrole:
            self = .stack
        default:
            return nil
        }
    }

    var subrole: String {
        switch self {
        case .single:
            return Config.notificationAlertSubrole
        case .stack:
            return Config.notificationAlertStackSubrole
        }
    }

    var actionNameFragment: String {
        switch self {
        case .single:
            return Config.notificationCloseActionNameFragment
        case .stack:
            return Config.notificationClearAllActionNameFragment
        }
    }

    var label: String {
        switch self {
        case .single:
            return "single"
        case .stack:
            return "stack"
        }
    }
}

struct VisibleNotificationItem {
    let element: AXUIElement
    let kind: VisibleNotificationKind
    let frame: CGRect

    var kindLabel: String {
        kind.label
    }

    var axSubrole: String {
        kind.subrole
    }

    var axIdentifier: String {
        strAttr(element, kAXIdentifierAttribute) ?? ""
    }

    var notificationAXKey: NotificationAXKey? {
        guard !axIdentifier.isEmpty else {
            return nil
        }

        return NotificationAXKey(
            subrole: axSubrole,
            axIdentifier: axIdentifier
        )
    }
    
    var isActionable: Bool {
        actions(element).contains { actionName in
            actionName.localizedCaseInsensitiveContains(kind.actionNameFragment)
        }
    }
}

func notificationSearchRoots(logFound: Bool = true) -> [AXUIElement] {
    var roots: [AXUIElement] = []

    for app in notificationCenterApplications() {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let windows = children(axApp, kAXWindowsAttribute)
        let notificationWindows = windows.filter(isNotificationCenterWindow)

        if logFound {
            debugLog("SEARCH NOTIFICATION APP: bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil") pid=\(app.processIdentifier) windows=\(windows.count) notificationWindows=\(notificationWindows.count)")
        }

        if notificationWindows.isEmpty {
            roots.append(axApp)
        } else {
            roots.append(contentsOf: notificationWindows)
        }
    }

    return roots
}

func isUsableVisibleNotificationItem(_ e: AXUIElement) -> Bool {
    if boolAttr(e, kAXHiddenAttribute) == true {
        return false
    }

    guard let frame = frameAttr(e) else {
        return false
    }

    return frame.size.width > 1 && frame.size.height > 1
}

func visibleNotificationItemIdentityKey(_ item: VisibleNotificationItem) -> String {
    let title = strAttr(item.element, kAXTitleAttribute) ?? ""
    let desc = strAttr(item.element, kAXDescriptionAttribute) ?? ""
    let id = strAttr(item.element, kAXIdentifierAttribute) ?? ""
    let actionKey = actions(item.element).joined(separator: "|")

    return [
        item.kind.rawValue,
        roundedFrameKey(item.frame),
        title,
        desc,
        id,
        actionKey
    ].joined(separator: "::")
}

func collectVisibleNotificationItems(
    _ e: AXUIElement,
    matchingKinds targetKinds: Set<VisibleNotificationKind>? = nil,
    depth: Int = 0,
    maxDepth: Int = Config.defaultAXTreeSearchMaxDepth,
    visited: inout Set<CFHashCode>,
    items: inout [VisibleNotificationItem]
) {
    if depth > maxDepth { return }

    let hash = CFHash(e)
    if visited.contains(hash) { return }
    visited.insert(hash)

    let subrole = strAttr(e, kAXSubroleAttribute) ?? ""

    if
        let kind = VisibleNotificationKind(subrole: subrole),
        targetKinds == nil || targetKinds!.contains(kind),
        isUsableVisibleNotificationItem(e),
        let frame = frameAttr(e)
    {
        items.append(
            VisibleNotificationItem(
                element: e,
                kind: kind,
                frame: frame
            )
        )
    }

    for name in [kAXVisibleChildrenAttribute, kAXChildrenAttribute, "AXChildrenInNavigationOrder"] {
        for child in children(e, name) {
            collectVisibleNotificationItems(
                child,
                matchingKinds: targetKinds,
                depth: depth + 1,
                maxDepth: maxDepth,
                visited: &visited,
                items: &items
            )
        }
    }
}

func sortVisibleNotificationItems(_ items: [VisibleNotificationItem]) -> [VisibleNotificationItem] {
    items.sorted { a, b in
        let yDelta = abs(a.frame.minY - b.frame.minY)
        if yDelta > 1.0 {
            return a.frame.minY < b.frame.minY
        }

        let xDelta = abs(a.frame.minX - b.frame.minX)
        if xDelta > 1.0 {
            // Notification banners and stacks usually live at the right edge.
            // For equal vertical positions, prefer the rightmost item.
            return a.frame.minX > b.frame.minX
        }

        return roundedFrameKey(a.frame) < roundedFrameKey(b.frame)
    }
}

func visibleNotificationItems(
    matchingKinds targetKinds: Set<VisibleNotificationKind>? = nil,
    debugDump: Bool = false
) -> [VisibleNotificationItem] {
    var allItems: [VisibleNotificationItem] = []

    for root in notificationSearchRoots(logFound: debugDump) {
        var visited = Set<CFHashCode>()
        collectVisibleNotificationItems(
            root,
            matchingKinds: targetKinds,
            visited: &visited,
            items: &allItems
        )
    }

    var seenItemKeys = Set<String>()
    var deduplicated: [VisibleNotificationItem] = []

    for item in allItems {
        let key = visibleNotificationItemIdentityKey(item)
        guard !seenItemKeys.contains(key) else { continue }

        seenItemKeys.insert(key)
        deduplicated.append(item)
    }

    let sorted = sortVisibleNotificationItems(deduplicated)

    if debugDump {
        debugLog("VISIBLE_SCAN: raw=\(allItems.count) deduplicated=\(deduplicated.count)")
        for (index, item) in sorted.enumerated() {
            debugLog("  [\(index)] kind=\(item.kindLabel) frame=\(formatFrame(item.frame)) actionable=\(item.isActionable) \(compactDescribe(item.element))")
        }
    }

    return sorted
}

func topVisibleNotificationItem(
    kind: VisibleNotificationKind
) -> VisibleNotificationItem? {
    visibleNotificationItems(matchingKinds: [kind]).first { item in
        item.isActionable
    }
}

func clearVisibleNotificationItem(_ item: VisibleNotificationItem) -> Bool {
    performFirstAction(on: item.element, nameContaining: item.kind.actionNameFragment)
}

func visibleNotificationAXKeyDisplayString(_ item: VisibleNotificationItem) -> String {
    item.notificationAXKey?.rawValue ?? "<missing AXIdentifier>"
}

func visibleNotificationItem(
    matching key: NotificationAXKey,
    in items: [VisibleNotificationItem]
) -> VisibleNotificationItem? {
    items.first { item in
        item.axSubrole == key.subrole &&
        item.axIdentifier == key.axIdentifier
    }
}

func visibleNotificationStableKey(_ item: VisibleNotificationItem) -> String {
    let id = strAttr(item.element, kAXIdentifierAttribute) ?? ""
    if !id.isEmpty {
        return "\(item.kind.rawValue)::id::\(id)"
    }

    let title = strAttr(item.element, kAXTitleAttribute) ?? ""
    let desc = strAttr(item.element, kAXDescriptionAttribute) ?? ""
    let actionKey = actions(item.element).joined(separator: "|")

    // Fallback for OS versions/elements that do not expose AXIdentifier.
    // Avoid frame here because notification frames move during animations.
    return [
        item.kind.rawValue,
        title,
        desc,
        actionKey
    ].joined(separator: "::")
}

func countVisibleNotificationItems(_ items: [VisibleNotificationItem], kind: VisibleNotificationKind) -> Int {
    items.filter { $0.kind == kind }.count
}

func topActionableVisibleNotificationItem(
    kind: VisibleNotificationKind,
    in items: [VisibleNotificationItem]
) -> VisibleNotificationItem? {
    items.first { item in
        item.kind == kind && item.isActionable
    }
}

func topActionableVisibleNotificationItem(
    in items: [VisibleNotificationItem]
) -> VisibleNotificationItem? {
    items.first { item in
        item.isActionable
    }
}

/// Waits until an AX action appears to have made real visible progress.
///
/// Important: AXUIElementPerformAction can return success even while the
/// notification remains visible during redraw/animation. This helper does not
/// assume that a successful AX action means a notification was actually removed.
func waitForVisibleNotificationProgress(
    afterClearing targetItem: VisibleNotificationItem,
    previousItems: [VisibleNotificationItem]
) -> Bool {
    let targetKey = visibleNotificationStableKey(targetItem)
    let previousAllCount = previousItems.count
    let previousKindCount = countVisibleNotificationItems(previousItems, kind: targetItem.kind)
    let deadline = Date().addingTimeInterval(Config.clearVisibleProgressTimeout)

    while Date() < deadline {
        let currentItems = visibleNotificationItems()
        let currentAllCount = currentItems.count
        let currentKindCount = countVisibleNotificationItems(currentItems, kind: targetItem.kind)
        let targetStillVisible = currentItems.contains { item in
            visibleNotificationStableKey(item) == targetKey
        }

        if !targetStillVisible || currentAllCount < previousAllCount || currentKindCount < previousKindCount {
            debugLog("CLEAR_VISIBLE: progress targetStillVisible=\(targetStillVisible) all=\(previousAllCount)->\(currentAllCount) kind=\(previousKindCount)->\(currentKindCount)")
            return true
        }

        Thread.sleep(forTimeInterval: Config.clearVisibleProgressPollingInterval)
    }

    debugLog("CLEAR_VISIBLE: no observed progress kind=\(targetItem.kindLabel) targetKey=\(shortenedAXText(targetKey, maxLength: 120))")
    return false
}

func visibleNotificationSummaryLines() -> [String] {
    visibleNotificationItems().enumerated().map { index, item in
        let actionList = actions(item.element).joined(separator: ", ")
        let key = visibleNotificationAXKeyDisplayString(item)

        return "\(index + 1). \(item.kindLabel) key=\"\(key)\" actionable=\(item.isActionable) frame=[\(formatFrame(item.frame))] actions=[\(actionList)] \(describe(item.element))"
    }
}

func dumpVisibleNotificationCandidates() {
    let lines = visibleNotificationSummaryLines()

    if lines.isEmpty {
        debugLog("DEBUG: no visible notification candidates found")
        return
    }

    for line in lines {
        debugLog("DEBUG: \(line)")
    }
}

// MARK: - Visible Notification Actions

extension ShutUpMac {
    /// Bare-bones targeted action.
    ///
    /// Finds the top visible single notification and performs its Name:Close action.
    /// This intentionally ignores stacks and does not expand them.
    static func closeTopVisibleNotification() -> Bool {
        let result = closeTopVisibleNotificationResult()
        return result.succeeded && result.didClear
    }
    
    /// Dismisses one currently visible notification or notification stack by
    /// its runtime AX key.
    ///
    /// The key format is:
    ///   <AXSubrole>|<AXIdentifier>
    ///
    /// This intentionally does not open Notification Center. The caller is
    /// expected to pass a key for an element that is currently visible.
    static func dismissVisibleNotification(matching key: NotificationAXKey) -> Bool {
        let result = dismissVisibleNotificationResult(matching: key)
        return result.succeeded && result.didClear
    }

    /// Result-returning variant for the CLI/logger integration.
    static func dismissVisibleNotificationResult(
        matching key: NotificationAXKey
    ) -> ClearNotificationsResult {
        debugLog("AX trusted: \(AXIsProcessTrusted())")

        guard VisibleNotificationKind(subrole: key.subrole) != nil else {
            return .failure(
                "Invalid notification key: unsupported subrole '\(key.subrole)'"
            )
        }

        let items = visibleNotificationItems(debugDump: Debug.isEnabled)

        guard let item = visibleNotificationItem(matching: key, in: items) else {
            dumpVisibleNotificationCandidates()
            return .failure("Notification not found for key: \(key.rawValue)")
        }

        debugLog("DISMISS_KEY: found \(item.kindLabel) key=\(key.rawValue) \(compactDescribe(item.element))")

        guard item.isActionable else {
            return .failure(
                "Notification found but not dismissible for key: \(key.rawValue)"
            )
        }

        guard clearVisibleNotificationItem(item) else {
            return .failure(
                "Notification found but dismiss action failed for key: \(key.rawValue)"
            )
        }

        let observedProgress = waitForVisibleNotificationProgress(
            afterClearing: item,
            previousItems: items
        )

        guard observedProgress else {
            return .failure(
                "Dismiss action was performed, but no visible progress was observed for key: \(key.rawValue)"
            )
        }

        switch item.kind {
        case .single:
            return .success(
                "SUCCESS: dismissed visible notification for key: \(key.rawValue)",
                didClear: true
            )

        case .stack:
            return .success(
                "SUCCESS: dismissed visible notification stack for key: \(key.rawValue)",
                didClear: true
            )
        }
    }

    /// Result-returning variant for the CLI.
    static func closeTopVisibleNotificationResult() -> ClearNotificationsResult {
        debugLog("AX trusted: \(AXIsProcessTrusted())")

        guard let item = topVisibleNotificationItem(kind: .single) else {
            dumpLikelySystemWindows()
            return .success("Nothing to clear: no visible single notification found", didClear: false)
        }

        debugLog("CLEAR_SINGLE: found top visible single notification \(compactDescribe(item.element))")

        if clearVisibleNotificationItem(item) {
            return .success("SUCCESS: cleared top visible single notification", didClear: true)
        }

        return .failure("Clear single notification failed")
    }

    /// Bare-bones targeted action.
    ///
    /// Finds the top visible notification stack and performs its Name:Clear All action.
    /// This intentionally ignores single notifications and does not expand stacks.
    static func clearTopVisibleStack() -> Bool {
        let result = clearTopVisibleStackResult()
        return result.succeeded && result.didClear
    }

    /// Result-returning variant for the CLI.
    static func clearTopVisibleStackResult() -> ClearNotificationsResult {
        debugLog("AX trusted: \(AXIsProcessTrusted())")

        guard let item = topVisibleNotificationItem(kind: .stack) else {
            dumpLikelySystemWindows()
            return .success("Nothing to clear: no visible notification stack found", didClear: false)
        }

        debugLog("CLEAR_STACK: found top visible notification stack \(compactDescribe(item.element))")

        if clearVisibleNotificationItem(item) {
            return .success("SUCCESS: cleared top visible notification stack", didClear: true)
        }

        return .failure("Clear stack failed")
    }

    /// Clears the top-most visible notification thing.
    ///
    /// If the top visible thing is a single notification, this performs its
    /// Name:Close action. If the top visible thing is a stack, this performs its
    /// Name:Clear All action.
    static func clearMostRecentVisibleNotification() -> Bool {
        let result = clearMostRecentVisibleNotificationResult()
        return result.succeeded && result.didClear
    }

    /// Result-returning variant for the GUI/CLI.
    static func clearMostRecentVisibleNotificationResult() -> ClearNotificationsResult {
        debugLog("AX trusted: \(AXIsProcessTrusted())")

        let items = visibleNotificationItems()

        guard let item = topActionableVisibleNotificationItem(in: items) else {
            dumpLikelySystemWindows()
            return .success("Nothing to clear: no visible notification or stack found", didClear: false)
        }

        debugLog("CLEAR_RECENT: found top visible \(item.kindLabel) \(compactDescribe(item.element))")

        if clearVisibleNotificationItem(item) {
            switch item.kind {
            case .single:
                return .success("SUCCESS: cleared most recent visible notification", didClear: true)
            case .stack:
                return .success("SUCCESS: cleared most recent visible notification stack", didClear: true)
            }
        }

        return .failure("Clear most recent notification failed")
    }

    /// Clears visible notifications without opening Notification Center.
    ///
    /// This repeatedly takes a fresh snapshot of visible single notifications and
    /// visible stacks, clears the top actionable item, waits briefly for macOS to
    /// update the AX tree, then repeats until nothing actionable is visible.
    static func clearVisibleNotifications() -> ClearNotificationsResult {
        let result = clearVisibleNotificationsResult()
        return result
    }

    /// Result-returning variant for the CLI.
    static func clearVisibleNotificationsResult() -> ClearNotificationsResult {
        debugLog("AX trusted: \(AXIsProcessTrusted())")

        var didClearAnything = false
        var actionCount = 0
        var observedProgressCount = 0
        var consecutiveNoProgressActions = 0

        for cycle in 1...Config.clearVisibleMaxCycles {
            let cycleStartItems = visibleNotificationItems()
            let cycleStartActionableItems = cycleStartItems.filter { $0.isActionable }

            if cycleStartActionableItems.isEmpty {
                if didClearAnything {
                    return .success(
                        "SUCCESS: cleared visible notifications with \(actionCount) AX action(s) and \(observedProgressCount) observed progress event(s)",
                        didClear: true
                    )
                } else {
                    return .success("Nothing to clear: no visible notifications found", didClear: false)
                }
            }

            let singleCount = countVisibleNotificationItems(cycleStartActionableItems, kind: .single)
            let stackCount = countVisibleNotificationItems(cycleStartActionableItems, kind: .stack)
            debugLog("CLEAR_VISIBLE: cycle=\(cycle) singles=\(singleCount) stacks=\(stackCount) total=\(cycleStartActionableItems.count)")

            // Order does not matter for the visible sweep. Clear singles first,
            // then stacks. Each action uses a fresh snapshot and waits for
            // observed progress before moving on.
            for kind in [VisibleNotificationKind.single, VisibleNotificationKind.stack] {
                while true {
                    let beforeItems = visibleNotificationItems()

                    guard let item = topActionableVisibleNotificationItem(kind: kind, in: beforeItems) else {
                        break
                    }

                    if actionCount >= Config.clearVisibleMaxActions {
                        return .failure(
                            "Stopped after \(actionCount) visible clear AX action(s); visible notifications may remain"
                        )
                    }

                    debugLog("CLEAR_VISIBLE: action=\(actionCount + 1) kind=\(item.kindLabel) frame=\(formatFrame(item.frame))")

                    guard clearVisibleNotificationItem(item) else {
                        return .failure("Clear visible failed on \(item.kindLabel) after \(actionCount) AX action(s)")
                    }

                    didClearAnything = true
                    actionCount += 1

                    let observedProgress = waitForVisibleNotificationProgress(
                        afterClearing: item,
                        previousItems: beforeItems
                    )

                    if observedProgress {
                        observedProgressCount += 1
                        consecutiveNoProgressActions = 0
                    } else {
                        consecutiveNoProgressActions += 1

                        if consecutiveNoProgressActions >= Config.clearVisibleMaxConsecutiveNoProgressActions {
                            return .failure(
                                "Stopped after \(actionCount) visible clear AX action(s); no visible progress was observed for \(consecutiveNoProgressActions) consecutive action(s)"
                            )
                        }
                    }
                }
            }
        }

        return .failure(
            "Stopped after \(Config.clearVisibleMaxCycles) visible clear cycle(s); visible notifications may remain"
        )
    }

    /// CLI/debug helper. Safe for the menu app to ignore.
    static func visibleNotificationSummaries() -> [String] {
        visibleNotificationSummaryLines()
    }
}
