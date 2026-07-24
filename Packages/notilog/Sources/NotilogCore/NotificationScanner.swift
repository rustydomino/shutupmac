import Foundation
import AppKit
import ApplicationServices

public struct VisibleNotification {
    public let key: String
    public let subrole: String
    public let axIdentifier: String
    public let app: String
    public let title: String
    public let subtitle: String
    public let body: String

    public init(
        key: String,
        subrole: String? = nil,
        axIdentifier: String? = nil,
        app: String,
        title: String,
        subtitle: String,
        body: String
    ) {
        let parsedKey = Self.parseKey(key)

        self.key = key
        self.subrole = subrole ?? parsedKey.subrole
        self.axIdentifier = axIdentifier ?? parsedKey.axIdentifier
        self.app = app
        self.title = title
        self.subtitle = subtitle
        self.body = body
    }

    public init(
        subrole: String,
        axIdentifier: String,
        app: String,
        title: String,
        subtitle: String,
        body: String
    ) {
        self.key = "\(subrole)|\(axIdentifier)"
        self.subrole = subrole
        self.axIdentifier = axIdentifier
        self.app = app
        self.title = title
        self.subtitle = subtitle
        self.body = body
    }

    private static func parseKey(_ key: String) -> (subrole: String, axIdentifier: String) {
        guard let separatorIndex = key.firstIndex(of: "|") else {
            return ("", key)
        }

        let subrole = String(key[..<separatorIndex])
        let identifierStart = key.index(after: separatorIndex)
        let axIdentifier = String(key[identifierStart...])

        return (subrole, axIdentifier)
    }
}

public struct ScannerDebugInfo {
    public let notificationCenterProcessCount: Int
    public let visitedAXElementCount: Int
    public let candidateNotificationCount: Int

    public init(notificationCenterProcessCount: Int, visitedAXElementCount: Int, candidateNotificationCount: Int) {
        self.notificationCenterProcessCount = notificationCenterProcessCount
        self.visitedAXElementCount = visitedAXElementCount
        self.candidateNotificationCount = candidateNotificationCount
    }
}

enum NotificationScannerConfig {
    static let notificationCenterBundleIDs = [
        "com.apple.notificationcenterui",
        "com.apple.UserNotificationCenter",
        "com.apple.notificationcenter"
    ]

    static let alertSubrole = "AXNotificationCenterAlert"
    static let stackSubrole = "AXNotificationCenterAlertStack"
}

func findTextValue(in root: AXUIElement, identifier: String, maxDepth: Int = 5) -> String {
    var visited = Set<String>()
    var result: String?

    func walk(_ element: AXUIElement, depth: Int) {
        if result != nil || depth > maxDepth {
            return
        }

        let key = elementKey(element)

        if visited.contains(key) {
            return
        }

        visited.insert(key)

        let id = strAttr(element, kAXIdentifierAttribute) ?? ""

        if id == identifier {
            if let value = strAttr(element, kAXValueAttribute), !value.isEmpty {
                result = value
                return
            }

            if let title = strAttr(element, kAXTitleAttribute), !title.isEmpty {
                result = title
                return
            }

            if let desc = strAttr(element, kAXDescriptionAttribute), !desc.isEmpty {
                result = desc
                return
            }
        }

        for childAttribute in [kAXChildrenAttribute, kAXVisibleChildrenAttribute, "AXChildrenInNavigationOrder"] {
            for child in children(element, childAttribute) {
                walk(child, depth: depth + 1)
            }
        }
    }

    walk(root, depth: 0)

    return result ?? ""
}

func appNameFromDescription(_ desc: String) -> String {
    let parts = desc
        .split(separator: ",", maxSplits: 1)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

    return parts.first ?? ""
}

public final class NotificationScanner {

    public init() {
    }
    
    private var dumpedDebugKeys = Set<String>()
    
    public private(set) var debugInfo = ScannerDebugInfo(notificationCenterProcessCount: 0, visitedAXElementCount: 0, candidateNotificationCount: 0)
    public func scan() -> [VisibleNotification] {
        let apps = notificationCenterApplications()

        let scanStats = scanAXElements(in: apps)

        debugInfo = ScannerDebugInfo(
            notificationCenterProcessCount: apps.count,
            visitedAXElementCount: scanStats.visitedCount,
            candidateNotificationCount: scanStats.candidateNotificationCount
        )
        return scanStats.notifications
    }

    private func notificationCenterApplications() -> [NSRunningApplication] {
        var apps: [NSRunningApplication] = []

        for bundleID in NotificationScannerConfig.notificationCenterBundleIDs {
            apps.append(contentsOf: NSRunningApplication.runningApplications(withBundleIdentifier: bundleID))
        }

        return apps
    }

    private func scanAXElements(in apps: [NSRunningApplication]) -> (
        visitedCount: Int,
        candidateNotificationCount: Int,
        notifications: [VisibleNotification]
    ) {

        var visited = Set<String>()
        var candidateNotificationCount = 0
        var notifications: [VisibleNotification] = []

        func walk(_ element: AXUIElement, depth: Int) {
            if depth > 12 {
                return
            }

            let key = elementKey(element)

            if visited.contains(key) {
                return
            }

            visited.insert(key)

            let subrole = strAttr(element, kAXSubroleAttribute) ?? ""

            if subrole == NotificationScannerConfig.alertSubrole || subrole == NotificationScannerConfig.stackSubrole {
                candidateNotificationCount += 1
                
                let notificationID = strAttr(element, kAXIdentifierAttribute) ?? elementKey(element)
                let notificationKey = "\(subrole)|\(notificationID)"

                if !dumpedDebugKeys.contains(notificationKey) {
                    dumpedDebugKeys.insert(notificationKey)

                    Debug.log("========== AX Notifiication Subtree ==========")
                    var debugVisited = Set<String>()
                    dumpAXSubtree(element, visited: &debugVisited)
                    Debug.log("=============================================")
                }

                notifications.append(
                    VisibleNotification(
                        subrole: subrole,
                        axIdentifier: notificationID,
                        app: appNameFromDescription(strAttr(element, kAXDescriptionAttribute) ?? ""),
                        title: findTextValue(in: element, identifier: "title"),
                        subtitle: findTextValue(in: element, identifier: "subtitle"),
                        body: findTextValue(in: element, identifier: "body")
                    )
                )
            }
            
            for childAttribute in [kAXChildrenAttribute, kAXVisibleChildrenAttribute, "AXChildrenInNavigationOrder"] {
                for child in children(element, childAttribute) {
                    walk(child, depth: depth + 1)
                }
            }
        }

        for app in apps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            walk(appElement, depth: 0)
        }

        var seenNotificationKeys = Set<String>()
        var uniqueNotifications: [VisibleNotification] = []

        for notification in notifications {
            if seenNotificationKeys.insert(notification.key).inserted {
                uniqueNotifications.append(notification)
            }
        }

        return (visited.count, candidateNotificationCount, uniqueNotifications)


    }

}
