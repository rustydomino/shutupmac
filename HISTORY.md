# ShutUpMac

## Overview

This project implements a native Swift command-line utility that
automatically clears macOS Notification Center using the Accessibility
(AX) API.

The objective was to eliminate brittle GUI automation (mouse clicks,
keyboard navigation, macro tools) and replace it with a robust
implementation that interacts directly with macOS accessibility objects.

Current implementation uses only the public Accessibility framework to:

-   Open Notification Center
-   Locate the "Clear Notifications..." control
-   Reveal the hidden context menu
-   Invoke **Clear All Notifications**
-   Close Notification Center

No mouse movement or synthetic mouse clicks are required.

------------------------------------------------------------------------

## Background

The original implementation relied on Keysmith to execute a keyboard
macro similar to:

``` text
Ctrl-Alt-Cmd-N
Tab
Tab
Space
Tab
Return
Escape
```

While functional, this depended entirely on keyboard focus and the
current accessibility tab order.

The goal became replacing this workflow with a native Swift
implementation.

------------------------------------------------------------------------

## Investigation

Several approaches were explored.

### AppleScript

AppleScript was able to send keyboard events (such as Escape) but could
not reliably discover or invoke the required Notification Center
controls.

Useful for prototyping, but insufficient as a complete solution.

### Hammerspoon

Hammerspoon was evaluated because it exposes the macOS Accessibility API
through Lua.

Significant progress was made:

-   dumping AX trees
-   identifying Notification Center objects
-   experimenting with UI traversal
-   testing AX actions

However, Hammerspoon was unable to reliably expose some of the controls
ultimately required for a fully native solution.

### Accessibility Inspector

Apple's Accessibility Inspector (part of Xcode) proved essential.

It revealed that the hidden "Clear All Notifications" control is **not**
a button.

Instead it appears as:

-   Role: `AXMenuItem`
-   Title: `Clear All Notifications`
-   Identifier: `menuAction:`

with actions including:

-   `AXPress`
-   `AXPick`
-   `AXCancel`

This discovery unlocked the native implementation.

------------------------------------------------------------------------

## Final Architecture

### Opening Notification Center

Rather than synthesizing a keyboard shortcut, the utility locates:

-   Application: `ControlCenter`
-   Menu Bar Item: `com.apple.menuextra.clock`

and invokes:

`AXPress`

Opening and closing Notification Center are both performed using the
same AX action.

------------------------------------------------------------------------

### Locating Notification Center

After opening:

-   perform a hit-test at a known location
-   obtain the parent chain
-   locate the Notification Center AXWindow

------------------------------------------------------------------------

### Finding the Clear Button

Recursively search the accessibility tree until locating:

-   Role: `AXMenuButton`
-   Identifier: `xmark`

This corresponds to the "Clear Notifications..." control.

------------------------------------------------------------------------

### Revealing the Menu

Invoke:

`AXShowMenu`

This causes the hidden menu item to appear.

------------------------------------------------------------------------

### Clearing Notifications

Recursively search again for:

-   Role: `AXMenuItem`
-   Title: `Clear All Notifications`

Invoke:

`AXPress`

Notifications are cleared immediately.

------------------------------------------------------------------------

### Closing Notification Center

Invoke `AXPress` again on the Clock menu bar item.

This cleanly dismisses Notification Center without keyboard simulation.

------------------------------------------------------------------------

## Technologies Used

-   Swift
-   ApplicationServices.framework
-   Accessibility (AX) API
-   CoreGraphics
-   AppKit
-   Accessibility Inspector (Xcode)

Historical tools used during reverse engineering:

-   Hammerspoon
-   AppleScript

------------------------------------------------------------------------

## Current Status

-   Native Swift implementation
-   No mouse movement
-   No mouse clicks
-   No keyboard navigation
-   No dependence on user-configured shortcuts
-   Pure Accessibility-based interaction

The remaining opportunities are primarily around polish (removing timing
sleeps by polling for state changes, improving resilience across macOS
releases, and packaging for distribution).

------------------------------------------------------------------------

## License

GPL2.0
