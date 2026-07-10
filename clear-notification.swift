import Foundation
import ApplicationServices
import CoreGraphics
import AppKit

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    let err = AXUIElementCopyAttributeValue(e, name as CFString, &value)
    return err == .success ? value : nil
}

func strAttr(_ e: AXUIElement, _ name: String) -> String? {
    attr(e, name) as? String
}

func children(_ e: AXUIElement, _ name: String) -> [AXUIElement] {
    attr(e, name) as? [AXUIElement] ?? []
}

func actions(_ e: AXUIElement) -> [String] {
    var value: CFArray?
    let err = AXUIElementCopyActionNames(e, &value)
    if err != .success { return [] }
    return (value as? [String]) ?? []
}

func describe(_ e: AXUIElement) -> String {
    let role = strAttr(e, kAXRoleAttribute) ?? "nil"
    let title = strAttr(e, kAXTitleAttribute) ?? "nil"
    let desc = strAttr(e, kAXDescriptionAttribute) ?? "nil"
    let id = strAttr(e, kAXIdentifierAttribute) ?? "nil"
    let acts = actions(e).joined(separator: ",")
    return "role=\(role) title=\(title) desc=\(desc) id=\(id) actions=[\(acts)]"
}

func elementAt(_ point: CGPoint) -> AXUIElement? {
    let system = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    let err = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element)
    print("ElementAtPosition \(point.x),\(point.y): \(err.rawValue) \(err)")
    return err == .success ? element : nil
}

func parentChain(_ e: AXUIElement) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var current: AXUIElement? = e

    while let node = current, result.count < 20 {
        result.append(node)
        if let parent = attr(node, kAXParentAttribute) {
            current = (parent as! AXUIElement)
        } else {
            current = nil
        }
    }

    return result
}

func findXmark(_ e: AXUIElement, depth: Int = 0, maxDepth: Int = 20) -> AXUIElement? {
    if depth > maxDepth { return nil }

    if strAttr(e, kAXRoleAttribute) == kAXMenuButtonRole as String,
       strAttr(e, kAXIdentifierAttribute) == "xmark" {
        return e
    }

    for name in [kAXChildrenAttribute, kAXVisibleChildrenAttribute, "AXChildrenInNavigationOrder"] {
        for child in children(e, name) {
            if let found = findXmark(child, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }
    }

    return nil
}

func findClearAll(_ e: AXUIElement, depth: Int = 0, maxDepth: Int = 20) -> AXUIElement? {
    if depth > maxDepth { return nil }

    if strAttr(e, kAXRoleAttribute) == kAXMenuItemRole as String,
       strAttr(e, kAXTitleAttribute) == "Clear All Notifications" {
        return e
    }

    for name in [kAXChildrenAttribute, kAXVisibleChildrenAttribute, "AXChildrenInNavigationOrder"] {
        for child in children(e, name) {
            if let found = findClearAll(child, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }
    }

    return nil
}

func findMenuExtra(_ e: AXUIElement, id targetID: String, depth: Int = 0, maxDepth: Int = 8) -> AXUIElement? {
    if depth > maxDepth { return nil }

    if strAttr(e, kAXIdentifierAttribute) == targetID {
        return e
    }

    for name in [kAXChildrenAttribute, kAXVisibleChildrenAttribute, "AXChildrenInNavigationOrder"] {
        for child in children(e, name) {
            if let found = findMenuExtra(child, id: targetID, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }
    }

    return nil
}

func press(_ e: AXUIElement) -> Bool {
    let err = AXUIElementPerformAction(e, kAXPressAction as CFString)
    print("AXPress result: \(err.rawValue) \(err)")
    return err == .success
}

func pressClockMenuExtra(label: String) -> Bool {
    guard let app = NSRunningApplication
        .runningApplications(withBundleIdentifier: "com.apple.controlcenter")
        .first else {
        print("ControlCenter not found")
        return false
    }

    let axApp = AXUIElementCreateApplication(app.processIdentifier)

    guard let clock = findMenuExtra(axApp, id: "com.apple.menuextra.clock") else {
        print("Clock menu extra not found")
        return false
    }

    print("FOUND CLOCK:", describe(clock))

    let err = AXUIElementPerformAction(clock, kAXPressAction as CFString)
    print("\(label) Clock AXPress result: \(err.rawValue) \(err)")
    return err == .success
}

func openNotificationCenterViaAX() -> Bool {
    pressClockMenuExtra(label: "Open")
}

func closeNotificationCenterViaAX() -> Bool {
    pressClockMenuExtra(label: "Close")
}

print("AX trusted: \(AXIsProcessTrusted())")

let knownPoint = CGPoint(x: 1373.3, y: 151.1)

guard openNotificationCenterViaAX() else {
    print("Could not open Notification Center")
    exit(1)
}

Thread.sleep(forTimeInterval: 0.20)

guard let underPoint = elementAt(knownPoint) else {
    print("Could not get element at known point")
    exit(1)
}

let chain = parentChain(underPoint)

guard let window = chain.first(where: {
    strAttr($0, kAXRoleAttribute) == kAXWindowRole as String &&
    strAttr($0, kAXTitleAttribute) == "Notification Center"
}) else {
    print("Notification Center window not found")
    exit(1)
}

print("WINDOW:", describe(window))

guard let xmark = findXmark(window) else {
    print("XMARK NOT FOUND")
    exit(1)
}

print("FOUND XMARK:", describe(xmark))

let showErr = AXUIElementPerformAction(xmark, kAXShowMenuAction as CFString)
print("AXShowMenu result: \(showErr.rawValue) \(showErr)")

Thread.sleep(forTimeInterval: 0.25)

guard let clearItem = findClearAll(window) else {
    print("CLEAR ITEM NOT FOUND")
    exit(1)
}

print("FOUND CLEAR ITEM:", describe(clearItem))

if press(clearItem) {
    Thread.sleep(forTimeInterval: 0.15)
    _ = closeNotificationCenterViaAX()
    print("SUCCESS")
    exit(0)
}

print("PRESS FAILED")
exit(1)