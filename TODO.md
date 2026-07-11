# ShutUpMac TODO

## High Priority

### Replace fixed sleeps with state polling

Current implementation uses fixed delays after opening Notification
Center, showing the menu, and clearing notifications. Replace these with
polling for the expected Accessibility state.

-   [ ] Wait for Notification Center window to appear
-   [ ] Wait for the Clear menu item to appear after `AXShowMenu`
-   [ ] Wait for Notification Center to dismiss after closing

------------------------------------------------------------------------

### Eliminate hard-coded hit-test coordinate

Current code depends on a fixed screen coordinate:

``` swift
let knownPoint = CGPoint(x: ..., y: ...)
```

Investigate locating the Notification Center window directly from the
Accessibility tree without relying on screen coordinates.

------------------------------------------------------------------------

### Gracefully handle "nothing to clear"

Treat these as successful no-op exits rather than failures.

-   [ ] No notifications present
-   [ ] No "Clear All Notifications" menu item
-   [ ] Notification Center contains only widgets

------------------------------------------------------------------------

## Robustness

-   [ ] Detect whether Notification Center was already open before
    running.
-   [ ] Restore the original Notification Center state on exit.
-   [ ] Verify behavior when notifications arrive during execution.
-   [ ] Improve resilience if Accessibility hierarchy changes.

------------------------------------------------------------------------

## Compatibility

Test on multiple macOS versions.

-   [ ] Ventura
-   [ ] Sonoma
-   [ ] Sequoia
-   [ ] Future releases

Document any Accessibility tree differences.

------------------------------------------------------------------------

## Display Configuration Testing

-   [ ] Single display
-   [ ] Multiple displays
-   [ ] Different scaling modes
-   [ ] Different menu bar locations

------------------------------------------------------------------------

## Notification Testing

Test with:

-   [ ] One notification
-   [ ] Multiple notifications
-   [ ] Grouped notifications
-   [ ] Persistent alerts
-   [ ] Different applications
-   [ ] Notification Summary enabled
-   [ ] Empty Notification Center

------------------------------------------------------------------------

## User Session Edge Cases

-   [ ] Locked screen
-   [ ] Sleeping Mac
-   [ ] Logged-out user
-   [ ] Fast User Switching
-   [ ] LaunchDaemon execution without active GUI

------------------------------------------------------------------------

## User Experience

-   [ ] Quiet mode
-   [ ] Verbose/debug mode
-   [ ] Cleaner logging
-   [ ] Optional exit codes for scripting

------------------------------------------------------------------------

## Documentation

-   [ ] Document tested macOS versions
-   [ ] Add architecture diagram
-   [ ] Add screenshots
-   [ ] Add animated demo GIF
-   [ ] Expand troubleshooting section

------------------------------------------------------------------------

## Security

-   [ ] Document Accessibility permission requirements
-   [ ] Explain why Accessibility permission is needed
-   [ ] Document privacy considerations

------------------------------------------------------------------------

## Future Ideas

-   [ ] Homebrew formula
-   [ ] Prebuilt universal binary releases
-   [ ] GitHub Actions for automatic builds
-   [ ] Swift Package Manager support
-   [ ] Optional filtering by application (if feasible)
-   [ ] Generalize into a reusable Accessibility helper library
