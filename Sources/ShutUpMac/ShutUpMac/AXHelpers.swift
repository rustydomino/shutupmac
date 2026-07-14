import Foundation
import ApplicationServices
import CoreGraphics

// MARK: - Generic AX Helpers

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    let err = AXUIElementCopyAttributeValue(e, name as CFString, &value)
    return err == .success ? value : nil
}

func strAttr(_ e: AXUIElement, _ name: String) -> String? {
    attr(e, name) as? String
}

func boolAttr(_ e: AXUIElement, _ name: String) -> Bool? {
    attr(e, name) as? Bool
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

func cgPointAttr(_ e: AXUIElement, _ name: String) -> CGPoint? {
    guard let value = attr(e, name) else { return nil }
    guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgPoint else { return nil }

    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
    return point
}

func cgSizeAttr(_ e: AXUIElement, _ name: String) -> CGSize? {
    guard let value = attr(e, name) else { return nil }
    guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgSize else { return nil }

    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
    return size
}

func frameAttr(_ e: AXUIElement) -> CGRect? {
    guard let position = cgPointAttr(e, kAXPositionAttribute) else { return nil }
    guard let size = cgSizeAttr(e, kAXSizeAttribute) else { return nil }
    return CGRect(origin: position, size: size)
}

func roundedFrameKey(_ rect: CGRect) -> String {
    let x = Int(rect.origin.x.rounded())
    let y = Int(rect.origin.y.rounded())
    let w = Int(rect.size.width.rounded())
    let h = Int(rect.size.height.rounded())
    return "x\(x)-y\(y)-w\(w)-h\(h)"
}

func formatFrame(_ rect: CGRect) -> String {
    String(
        format: "x=%.0f y=%.0f w=%.0f h=%.0f",
        rect.origin.x,
        rect.origin.y,
        rect.size.width,
        rect.size.height
    )
}

func describe(_ e: AXUIElement) -> String {
    let role = strAttr(e, kAXRoleAttribute) ?? "nil"
    let subrole = strAttr(e, kAXSubroleAttribute) ?? "nil"
    let title = strAttr(e, kAXTitleAttribute) ?? "nil"
    let desc = strAttr(e, kAXDescriptionAttribute) ?? "nil"
    let id = strAttr(e, kAXIdentifierAttribute) ?? "nil"
    let acts = actions(e).joined(separator: ",")
    let focused = boolAttr(e, kAXFocusedAttribute).map { String($0) } ?? "nil"

    let frameDescription: String
    if let frame = frameAttr(e) {
        frameDescription = formatFrame(frame)
    } else {
        frameDescription = "nil"
    }

    return "role=\(role) subrole=\(subrole) title=\(title) desc=\(desc) id=\(id) focused=\(focused) frame=\(frameDescription) actions=[\(acts)]"
}

func shortenedAXText(_ value: String?, maxLength: Int = 80) -> String {
    guard let value, !value.isEmpty else { return "nil" }

    let cleaned = value
        .replacingOccurrences(of: "\n", with: "\\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard cleaned.count > maxLength else { return cleaned }
    return String(cleaned.prefix(maxLength)) + "..."
}

func compactDescribe(_ e: AXUIElement, maxTextLength: Int = 80) -> String {
    let role = strAttr(e, kAXRoleAttribute) ?? "nil"
    let subrole = strAttr(e, kAXSubroleAttribute) ?? "nil"
    let title = shortenedAXText(strAttr(e, kAXTitleAttribute), maxLength: maxTextLength)
    let desc = shortenedAXText(strAttr(e, kAXDescriptionAttribute), maxLength: maxTextLength)
    let id = shortenedAXText(strAttr(e, kAXIdentifierAttribute), maxLength: maxTextLength)
    let frameDescription = frameAttr(e).map(formatFrame) ?? "nil"
    let acts = actions(e).joined(separator: ",")

    return "role=\(role) subrole=\(subrole) title=\(title) desc=\(desc) id=\(id) frame=\(frameDescription) actions=[\(acts)]"
}

func waitUntil(
    timeout: TimeInterval = Config.defaultPollingTimeout,
    interval: TimeInterval = Config.defaultPollingInterval,
    condition: () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        if condition() {
            return true
        }

        Thread.sleep(forTimeInterval: interval)
    }

    return false
}

func press(_ e: AXUIElement) -> Bool {
    let err = AXUIElementPerformAction(e, kAXPressAction as CFString)
    debugLog("AXPress result: \(err.rawValue) \(err)")
    return err == .success
}

func performAction(_ actionName: String, on e: AXUIElement) -> Bool {
    let err = AXUIElementPerformAction(e, actionName as CFString)
    debugLog("AX action \(actionName) result: \(err.rawValue) \(err)")
    return err == .success
}

func performFirstAction(on e: AXUIElement, nameContaining needle: String) -> Bool {
    guard let actionName = actions(e).first(where: { actionName in
        actionName.localizedCaseInsensitiveContains(needle)
    }) else {
        debugLog("No AX action containing \(needle) found on element: \(describe(e))")
        return false
    }

    return performAction(actionName, on: e)
}

// MARK: - AX Tree Search

/// Performs a depth-limited search through an Accessibility tree.
///
/// The search checks common child collections used by macOS Accessibility APIs,
/// including visible children and navigation-order children.
func findElement(
    _ e: AXUIElement,
    depth: Int = 0,
    maxDepth: Int = Config.defaultAXTreeSearchMaxDepth,
    matches: (AXUIElement) -> Bool
) -> AXUIElement? {
    if depth > maxDepth { return nil }

    if matches(e) {
        return e
    }

    for name in [kAXChildrenAttribute, kAXVisibleChildrenAttribute, "AXChildrenInNavigationOrder"] {
        for child in children(e, name) {
            if let found = findElement(child, depth: depth + 1, maxDepth: maxDepth, matches: matches) {
                return found
            }
        }
    }

    return nil
}
