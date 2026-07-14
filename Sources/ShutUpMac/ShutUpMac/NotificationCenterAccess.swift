/*
 Notification Center access helpers.

 This file contains the plumbing for finding, opening, raising, and closing
 Notification Center through Accessibility. It intentionally does not contain
 the actual notification-clearing workflows; those remain in ShutUpMacEngine.swift.
*/

import Foundation
import ApplicationServices
import AppKit

// MARK: - Clock Menu Extra Search

func findClockMenuExtra(
    _ e: AXUIElement,
    depth: Int = 0,
    maxDepth: Int = Config.defaultAXTreeSearchMaxDepth
) -> AXUIElement? {
    findElement(e, depth: depth, maxDepth: maxDepth) { node in
        let role = strAttr(node, kAXRoleAttribute) ?? ""
        let title = strAttr(node, kAXTitleAttribute) ?? ""
        let desc = strAttr(node, kAXDescriptionAttribute) ?? ""
        let id = strAttr(node, kAXIdentifierAttribute) ?? ""

        let looksLikeClock =
            id == Config.clockMenuExtraIdentifier ||
            title.localizedCaseInsensitiveContains("clock") ||
            desc.localizedCaseInsensitiveContains("clock") ||
            title.localizedCaseInsensitiveContains("date") ||
            desc.localizedCaseInsensitiveContains("date")

        let isPressable =
            actions(node).contains(kAXPressAction as String)

        let isMenuBarThing =
            role == kAXMenuBarItemRole as String ||
            role == kAXButtonRole as String

        return looksLikeClock && isPressable && isMenuBarThing
    }
}

// MARK: - Notification Center Detection

func isNotificationCenterWindow(_ e: AXUIElement) -> Bool {
    strAttr(e, kAXRoleAttribute) == kAXWindowRole as String &&
    strAttr(e, kAXTitleAttribute) == Config.notificationCenterWindowTitle
}

func axWindows(for app: NSRunningApplication) -> [AXUIElement] {
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    return children(axApp, kAXWindowsAttribute)
}

/// Returns running applications that may host Notification Center UI.
///
/// macOS has used multiple bundle identifiers for Notification Center across
/// releases, so callers should search all known candidates rather than relying
/// on a single bundle identifier.
func notificationCenterApplications() -> [NSRunningApplication] {
    var seenPIDs = Set<pid_t>()
    var apps: [NSRunningApplication] = []

    for bundleID in Config.notificationCenterBundleIDs {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            guard !seenPIDs.contains(app.processIdentifier) else { continue }
            seenPIDs.insert(app.processIdentifier)
            apps.append(app)
        }
    }

    return apps
}

/// Returns all Accessibility windows that appear to be Notification Center windows.
///
/// Important: the presence of a Notification Center AXWindow does not always mean
/// Notification Center is actually open. A visible notification banner can also
/// create a full-screen Notification Center AXWindow. Callers that need to know
/// whether the actual Notification Center panel is open should use
/// notificationCenterOpenPanelWindow().
func notificationCenterWindows(logFound: Bool = true) -> [AXUIElement] {
    var windows: [AXUIElement] = []

    for app in notificationCenterApplications() {
        let matchingWindows = axWindows(for: app).filter(isNotificationCenterWindow)

        if logFound && !matchingWindows.isEmpty {
            debugLog("FOUND NOTIFICATION CENTER APP: bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil") pid=\(app.processIdentifier)")
        }

        windows.append(contentsOf: matchingWindows)
    }

    return windows
}

/// Returns true when a node appears to be part of the actual open Notification Center panel.
///
/// Testing showed that a notification banner can create a Notification Center AXWindow
/// even when Notification Center itself is closed. The actual open panel exposes
/// additional controls, including:
///
/// - the Clear Notifications menu button with identifier "xmark"
/// - the Edit Widgets button with identifier "widget-editor-button"
/// - the widget grid with subrole "AXOpaqueProviderGrid"
func isNotificationCenterOpenPanelMarker(_ e: AXUIElement) -> Bool {
    let id = strAttr(e, kAXIdentifierAttribute) ?? ""
    let subrole = strAttr(e, kAXSubroleAttribute) ?? ""

    if id == Config.clearButtonIdentifier {
        return true
    }

    if id == Config.widgetEditorButtonIdentifier {
        return true
    }

    if subrole == Config.widgetGridSubrole {
        return true
    }

    return false
}

/// Returns true when this Notification Center AXWindow contains controls that only
/// appear when the full Notification Center panel is actually open.
func isNotificationCenterOpenPanelWindow(_ window: AXUIElement) -> Bool {
    findElement(window, maxDepth: Config.defaultAXTreeSearchMaxDepth) { node in
        isNotificationCenterOpenPanelMarker(node)
    } != nil
}

/// Returns the Notification Center window only if the actual panel appears open.
///
/// This is stricter than checking for the Notification Center AXWindow alone.
/// It avoids false positives caused by ordinary notification banners.
func notificationCenterOpenPanelWindow(logFound: Bool = true) -> AXUIElement? {
    for window in notificationCenterWindows(logFound: logFound) {
        if isNotificationCenterOpenPanelWindow(window) {
            debugLog("FOUND OPEN NOTIFICATION CENTER PANEL: \(describe(window))")
            return window
        }
    }

    return nil
}

/// Returns true when the actual Notification Center panel appears to be visibly open.
func isNotificationCenterOpen() -> Bool {
    notificationCenterOpenPanelWindow(logFound: false) != nil
}

/// Waits briefly for the actual Notification Center panel to appear.
///
/// Opening Notification Center through the menu extra is asynchronous, so the
/// open-panel controls may not be available immediately after pressing the Clock item.
func waitForNotificationCenterOpenPanelWindow() -> AXUIElement? {
    var panelWindow: AXUIElement?

    let found = waitUntil(timeout: Config.defaultPollingTimeout, interval: Config.defaultPollingInterval) {
        panelWindow = notificationCenterOpenPanelWindow(logFound: false)
        return panelWindow != nil
    }

    guard found, let panelWindow else {
        return nil
    }

    debugLog("FOUND NOTIFICATION CENTER OPEN PANEL WINDOW: \(describe(panelWindow))")

    if actions(panelWindow).contains(kAXRaiseAction as String) {
        let raiseErr = AXUIElementPerformAction(panelWindow, kAXRaiseAction as CFString)
        debugLog("Notification Center AXRaise result: \(raiseErr.rawValue) \(raiseErr)")
    }

    return panelWindow
}

// MARK: - Notification Center Actions

/// Presses the Clock menu extra, which toggles Notification Center.
///
/// Notification Center does not expose a simple public API for opening and
/// closing, so this uses the Accessibility representation of the menu bar Clock.
func pressClockMenuExtra(label: String) -> Bool {
    let candidateBundleIDs = [
        Config.controlCenterBundleID,
        Config.systemUIServerBundleID
    ]

    for bundleID in candidateBundleIDs {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)

        for app in apps {
            debugLog("Searching for Clock in app: bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil") pid=\(app.processIdentifier)")

            let axApp = AXUIElementCreateApplication(app.processIdentifier)

            if let clock = findClockMenuExtra(axApp) {
                debugLog("FOUND CLOCK: \(describe(clock))")

                let err = AXUIElementPerformAction(clock, kAXPressAction as CFString)
                debugLog("\(label) Clock AXPress result: \(err.rawValue) \(err)")

                return err == .success
            }

            debugLog("Clock not found in \(app.bundleIdentifier ?? "nil")")
        }
    }

    print("Clock menu extra not found")
    return false
}

func openNotificationCenterViaAX() -> Bool {
    pressClockMenuExtra(label: "Open")
}

func closeNotificationCenterViaAX() -> Bool {
    pressClockMenuExtra(label: "Close")
}

/// Ensures the actual Notification Center panel is open.
///
/// The Clock menu extra is a toggle, so this function first checks whether the
/// open panel is already present. It only presses the Clock item if the panel
/// does not appear to be open.
func ensureNotificationCenterOpen() -> AXUIElement? {
    if let existingWindow = notificationCenterOpenPanelWindow(logFound: false) {
        debugLog("Notification Center panel already open")
        return existingWindow
    }

    debugLog("Notification Center panel not open; pressing Clock to open")

    guard openNotificationCenterViaAX() else {
        return nil
    }

    return waitForNotificationCenterOpenPanelWindow()
}

/// Ensures the actual Notification Center panel is closed.
///
/// The Clock menu extra is a toggle, so this function checks the panel state
/// after pressing and retries if necessary.
func ensureNotificationCenterClosed() {
    for attempt in 1...Config.notificationCenterCloseRetries {
        if !isNotificationCenterOpen() {
            debugLog("Notification Center panel is closed")
            return
        }

        debugLog("Notification Center panel still open; close attempt \(attempt)")

        _ = closeNotificationCenterViaAX()

        let closed = waitUntil(timeout: 0.75, interval: Config.defaultPollingInterval) {
            !isNotificationCenterOpen()
        }

        if closed {
            debugLog("Notification Center panel closed")
            return
        }

        Thread.sleep(forTimeInterval: Config.notificationCenterCloseRetryDelay)
    }

    debugLog("Notification Center panel still appears open after close retries")
}
