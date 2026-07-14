/*
 Diagnostic Accessibility dump helpers for reverse-engineering Notification Center.

 This file intentionally contains noisy inspection tools used by the CLI
 --ax-dump command. Normal clear-all and visible-clear behavior should not
 depend on these routines except for concise failure diagnostics.
*/

import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - Diagnostics

/// Dumps candidate Notification Center Accessibility windows for troubleshooting.
///
/// This is only useful when window discovery fails, especially after macOS UI or
/// Accessibility behavior changes.
func dumpInterestingAXTree(
    _ e: AXUIElement,
    depth: Int = 0,
    maxDepth: Int = 6,
    maxNodes: Int = 200,
    counter: inout Int
) {
    if depth > maxDepth { return }
    if counter >= maxNodes { return }

    counter += 1

    let role = strAttr(e, kAXRoleAttribute) ?? ""
    let subrole = strAttr(e, kAXSubroleAttribute) ?? ""
    let title = strAttr(e, kAXTitleAttribute) ?? ""
    let desc = strAttr(e, kAXDescriptionAttribute) ?? ""
    let id = strAttr(e, kAXIdentifierAttribute) ?? ""
    let acts = actions(e)

    let hasInterestingText =
        !title.isEmpty ||
        !desc.isEmpty ||
        !id.isEmpty ||
        !subrole.isEmpty ||
        !acts.isEmpty ||
        role.localizedCaseInsensitiveContains("menu") ||
        role.localizedCaseInsensitiveContains("button") ||
        subrole.localizedCaseInsensitiveContains("notification")

    if hasInterestingText {
        let indent = String(repeating: "  ", count: depth)
        debugLog("\(indent)\(describe(e))")
    }

    for name in [kAXChildrenAttribute, kAXVisibleChildrenAttribute, "AXChildrenInNavigationOrder"] {
        for child in children(e, name) {
            dumpInterestingAXTree(
                child,
                depth: depth + 1,
                maxDepth: maxDepth,
                maxNodes: maxNodes,
                counter: &counter
            )
        }
    }
}

func dumpAXTreeForClockSearch(app: NSRunningApplication) {
    debugLog("DEBUG: AX tree for app bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil") pid=\(app.processIdentifier)")

    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var counter = 0

    dumpInterestingAXTree(
        axApp,
        maxDepth: 8,
        maxNodes: 300,
        counter: &counter
    )

    debugLog("DEBUG: dumped \(counter) AX nodes")
}

func dumpLikelySystemWindows() {
    debugLog("DEBUG: AX windows from Notification Center candidate apps:")

    for app in notificationCenterApplications() {
        let windows = axWindows(for: app)

        if windows.isEmpty {
            debugLog("  app bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil") pid=\(app.processIdentifier) windows=[]")
        } else {
            for window in windows {
                debugLog("  app bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil") pid=\(app.processIdentifier) window=\(describe(window))")
            }
        }
    }
}

struct AXDumpCandidate {
    let appName: String
    let bundleID: String
    let pid: pid_t
    let element: AXUIElement
    let frame: CGRect?
    let role: String?
    let subrole: String?
    let identifier: String?
    let title: String?
    let desc: String?
    let help: String?
    let actions: [String]
    let reasons: [String]
    let path: [String]
}

struct AXDumpMenuItem {
    let role: String?
    let title: String?
    let desc: String?
    let frame: CGRect?
    let actions: [String]
}

func formatFrameWithMaxY(_ rect: CGRect?) -> String {
    guard let rect else { return "nil" }

    return String(
        format: "x=%.0f y=%.0f w=%.0f h=%.0f maxY=%.0f",
        rect.origin.x,
        rect.origin.y,
        rect.size.width,
        rect.size.height,
        rect.maxY
    )
}

func axDumpElementPathPart(_ element: AXUIElement) -> String {
    let role = strAttr(element, kAXRoleAttribute) ?? "?"
    let subrole = strAttr(element, kAXSubroleAttribute)
    let identifier = strAttr(element, kAXIdentifierAttribute)
    let title = strAttr(element, kAXTitleAttribute)
    let desc = strAttr(element, kAXDescriptionAttribute)

    var pieces = [role]

    if let subrole, !subrole.isEmpty {
        pieces.append("subrole=\(subrole)")
    }

    if let identifier, !identifier.isEmpty {
        pieces.append("id=\(shortenedAXText(identifier, maxLength: 36))")
    }

    if let title, !title.isEmpty {
        pieces.append("title=\(shortenedAXText(title, maxLength: 36))")
    } else if let desc, !desc.isEmpty {
        pieces.append("desc=\(shortenedAXText(desc, maxLength: 36))")
    }

    return pieces.joined(separator: " ")
}

func axDumpReasons(
    role: String?,
    subrole: String?,
    identifier: String?,
    title: String?,
    desc: String?,
    help: String?,
    actions: [String]
) -> [String] {
    var reasons: [String] = []

    let text = [role, subrole, identifier, title, desc, help]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

    let actionText = actions.joined(separator: " ").lowercased()
    let roleText = role ?? ""

    if identifier?.localizedCaseInsensitiveContains(Config.clearButtonIdentifier) == true {
        reasons.append("identifier contains xmark")
    }

    if text.contains("clear") {
        reasons.append("text contains clear")
    }

    if text.contains("close") {
        reasons.append("text contains close")
    }

    if text.contains("notification") {
        reasons.append("text contains notification")
    }

    if actions.contains(kAXShowMenuAction as String) {
        reasons.append("has AXShowMenu")
    }

    if actionText.contains("clear") {
        reasons.append("action contains clear")
    }

    if actionText.contains("close") {
        reasons.append("action contains close")
    }

    if subrole == Config.notificationAlertSubrole || subrole == Config.notificationAlertStackSubrole {
        reasons.append("notification item")
    }

    if (
        roleText == kAXButtonRole as String ||
        roleText == kAXMenuButtonRole as String
    ), !reasons.isEmpty {
        reasons.append("button-like")
    }

    return reasons
}

func collectAXDumpCandidates(
    _ element: AXUIElement,
    appName: String,
    bundleID: String,
    pid: pid_t,
    path: [String],
    depth: Int = 0,
    maxDepth: Int = Config.defaultAXTreeSearchMaxDepth,
    visited: inout Set<CFHashCode>,
    candidates: inout [AXDumpCandidate]
) {
    if depth > maxDepth { return }

    let hash = CFHash(element)
    if visited.contains(hash) { return }
    visited.insert(hash)

    let role = strAttr(element, kAXRoleAttribute)
    let subrole = strAttr(element, kAXSubroleAttribute)
    let identifier = strAttr(element, kAXIdentifierAttribute)
    let title = strAttr(element, kAXTitleAttribute)
    let desc = strAttr(element, kAXDescriptionAttribute)
    let help = strAttr(element, kAXHelpAttribute)
    let elementActions = actions(element)
    let reasons = axDumpReasons(
        role: role,
        subrole: subrole,
        identifier: identifier,
        title: title,
        desc: desc,
        help: help,
        actions: elementActions
    )

    let currentPath = path + [axDumpElementPathPart(element)]

    if !reasons.isEmpty {
        candidates.append(
            AXDumpCandidate(
                appName: appName,
                bundleID: bundleID,
                pid: pid,
                element: element,
                frame: frameAttr(element),
                role: role,
                subrole: subrole,
                identifier: identifier,
                title: title,
                desc: desc,
                help: help,
                actions: elementActions,
                reasons: reasons,
                path: currentPath
            )
        )
    }

    for name in [kAXVisibleChildrenAttribute, kAXChildrenAttribute, "AXChildrenInNavigationOrder"] {
        for child in children(element, name) {
            collectAXDumpCandidates(
                child,
                appName: appName,
                bundleID: bundleID,
                pid: pid,
                path: currentPath,
                depth: depth + 1,
                maxDepth: maxDepth,
                visited: &visited,
                candidates: &candidates
            )
        }
    }
}

func collectAXDumpMenuItems(
    _ element: AXUIElement,
    depth: Int = 0,
    maxDepth: Int = 12,
    visited: inout Set<CFHashCode>,
    items: inout [AXDumpMenuItem]
) {
    if depth > maxDepth { return }

    let hash = CFHash(element)
    if visited.contains(hash) { return }
    visited.insert(hash)

    let role = strAttr(element, kAXRoleAttribute)
    let title = strAttr(element, kAXTitleAttribute)
    let desc = strAttr(element, kAXDescriptionAttribute)
    let elementFrame = frameAttr(element)
    let elementActions = actions(element)

    let roleText = role?.lowercased() ?? ""
    let text = [title, desc]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

    let hasRelevantText =
        text.contains("clear") ||
        text.contains("notification") ||
        text.contains("mute") ||
        text.contains("turn off") ||
        text.contains("settings")

    let isRealMenu =
        (roleText.contains("menu") || roleText.contains("button")) &&
        ((elementFrame?.width ?? 0) > 1) &&
        ((elementFrame?.height ?? 0) > 1)

    if hasRelevantText || isRealMenu {
        items.append(
            AXDumpMenuItem(
                role: role,
                title: title,
                desc: desc,
                frame: elementFrame,
                actions: elementActions
            )
        )
    }

    for name in [kAXVisibleChildrenAttribute, kAXChildrenAttribute, "AXChildrenInNavigationOrder"] {
        for child in children(element, name) {
            collectAXDumpMenuItems(
                child,
                depth: depth + 1,
                maxDepth: maxDepth,
                visited: &visited,
                items: &items
            )
        }
    }
}

func pressEscapeForAXDump() {
    let source = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)

    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

func dumpNotificationCenterAXControlsImpl(probeMenus: Bool) {
    print("AX trusted: \(AXIsProcessTrusted())")

    var allCandidates: [AXDumpCandidate] = []

    for app in notificationCenterApplications() {
        let bundleID = app.bundleIdentifier ?? "unknown"
        let appName = app.localizedName ?? "unknown"
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        let windows = children(axApp, kAXWindowsAttribute)
        let notificationWindows = windows.filter(isNotificationCenterWindow)
        let roots = notificationWindows.isEmpty ? [axApp] : notificationWindows

        print("APP: \(appName) bundle=\(bundleID) pid=\(pid) windows=\(windows.count) notificationWindows=\(notificationWindows.count)")

        if notificationWindows.isEmpty {
            var visited = Set<CFHashCode>()
            collectAXDumpCandidates(
                axApp,
                appName: appName,
                bundleID: bundleID,
                pid: pid,
                path: ["\(appName) pid=\(pid)", "app"],
                visited: &visited,
                candidates: &allCandidates
            )
        } else {
            for window in roots {
                let title = strAttr(window, kAXTitleAttribute)
                print("  WINDOW: title=\(shortenedAXText(title, maxLength: 80)) frame=\(formatFrameWithMaxY(frameAttr(window)))")

                var visited = Set<CFHashCode>()
                collectAXDumpCandidates(
                    window,
                    appName: appName,
                    bundleID: bundleID,
                    pid: pid,
                    path: ["\(appName) pid=\(pid)", "window=\(shortenedAXText(title, maxLength: 80))"],
                    visited: &visited,
                    candidates: &allCandidates
                )
            }
        }
    }

    let candidates = allCandidates.sorted { left, right in
        let leftMaxY = left.frame?.maxY ?? -Double.greatestFiniteMagnitude
        let rightMaxY = right.frame?.maxY ?? -Double.greatestFiniteMagnitude

        if leftMaxY != rightMaxY {
            return leftMaxY > rightMaxY
        }

        return (left.frame?.minX ?? 0) > (right.frame?.minX ?? 0)
    }

    print("")
    print("FOUND \(candidates.count) suspicious Notification Center AX candidate(s), sorted bottom-to-top")
    print("")

    for (index, candidate) in candidates.enumerated() {
        print("[\(index)]")
        print("  app: \(candidate.appName) bundle=\(candidate.bundleID) pid=\(candidate.pid)")
        print("  frame: \(formatFrameWithMaxY(candidate.frame))")
        print("  role: \(shortenedAXText(candidate.role, maxLength: 80))")
        print("  subrole: \(shortenedAXText(candidate.subrole, maxLength: 80))")
        print("  identifier: \(shortenedAXText(candidate.identifier, maxLength: 80))")
        print("  title: \(shortenedAXText(candidate.title, maxLength: 100))")
        print("  desc: \(shortenedAXText(candidate.desc, maxLength: 100))")
        print("  help: \(shortenedAXText(candidate.help, maxLength: 100))")
        print("  actions: \(candidate.actions.joined(separator: ", "))")
        print("  reasons: \(candidate.reasons.joined(separator: ", "))")
        print("  path:")

        for pathPart in candidate.path {
            print("    \(pathPart)")
        }

        if probeMenus, candidate.actions.contains(kAXShowMenuAction as String) {
            print("  menu probe:")

            let result = AXUIElementPerformAction(candidate.element, kAXShowMenuAction as CFString)
            print("    AXShowMenu result: \(result.rawValue) \(result)")
            Thread.sleep(forTimeInterval: 0.25)

            let axApp = AXUIElementCreateApplication(candidate.pid)
            var visited = Set<CFHashCode>()
            var menuItems: [AXDumpMenuItem] = []
            collectAXDumpMenuItems(
                axApp,
                visited: &visited,
                items: &menuItems
            )

            if menuItems.isEmpty {
                print("    no relevant menu-ish items found after AXShowMenu")
            } else {
                for (menuIndex, item) in menuItems.prefix(60).enumerated() {
                    print("    [menu \(menuIndex)] role=\(shortenedAXText(item.role, maxLength: 60)) title=\(shortenedAXText(item.title, maxLength: 100)) desc=\(shortenedAXText(item.desc, maxLength: 100)) frame=\(formatFrameWithMaxY(item.frame)) actions=\(item.actions.joined(separator: ", "))")
                }

                if menuItems.count > 60 {
                    print("    ... \(menuItems.count - 60) additional relevant menu-ish item(s) omitted")
                }
            }

            pressEscapeForAXDump()
            Thread.sleep(forTimeInterval: 0.10)
        }

        print("")
    }
}
