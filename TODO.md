# ShutUpMac TODO

## Recently Completed

### ✅ Replace fixed sleeps with state polling

Completed.

The implementation now uses polling of Accessibility state instead of
fixed delays wherever practical.

Completed work:

* Wait for Notification Center window to become available.
* Wait for the "Clear All Notifications" menu item after invoking
  `AXShowMenu`.
* Poll instead of relying on arbitrary sleep durations.

---

### ✅ Eliminate hard-coded Notification Center hit-test coordinate

Completed.

The original implementation relied on a fixed screen coordinate and
`AXUIElementCreateSystemWide()` hit-testing to locate Notification Center.

This has been completely removed.

Current implementation:

* Opens Notification Center by performing `AXPress` on the Clock menu
  extra (`com.apple.menuextra.clock`).
* Locates Notification Center by enumerating the Notification Center
  Accessibility windows.
* No screen coordinates are required.

This makes the implementation display-independent and significantly more
robust.

---

### ✅ Preserve Notification Center open/closed state

Completed.

The script now determines whether Notification Center was already open
before performing any work.

Final implementation:

* Enumerate Notification Center AX windows.
* Treat Notification Center as **open only if**

  * the Notification Center window exists, **and**
  * `AXFocused == true`.
* Otherwise treat Notification Center as closed.

Behavior:

* If the script opened Notification Center, it closes it before exiting.
* If Notification Center was already open, it is intentionally left open.

This avoids disrupting the user's workspace.

---

### ✅ Gracefully handle "nothing to clear"

Completed.

These conditions are treated as successful no-op exits.

* No notifications present.
* No Clear button available.
* No "Clear All Notifications" menu item.

---

## High Priority

### Verify Notification Center dismissal

Current implementation closes Notification Center only if it opened it.

Improve robustness by polling for successful dismissal rather than
assuming the AXPress succeeded.

* [ ] Wait until Notification Center loses focus or disappears.
* [ ] Report timeout if dismissal never occurs.

---

## Robustness

* [ ] Verify behavior if a notification arrives while the script is running.
* [ ] Improve resilience if Apple's Accessibility hierarchy changes.
* [ ] Reduce duplicate Notification Center lookup code.
* [ ] Refactor Notification Center detection helpers into a single module.
* [ ] Add optional DEBUG logging switch.

---

## Notification Center Edge Cases

Test the finalized implementation with:

* [ ] Notification Center containing only widgets.
* [ ] Notification Center with one notification.
* [ ] Notification Center with multiple notifications.
* [ ] Grouped notifications.
* [ ] Multiple notification groups.
* [ ] Mixed applications.
* [ ] Persistent alert-style notifications.
* [ ] Banner notifications while Notification Center is open.
* [ ] Notification arrives while script is running.
* [ ] Notification arrives immediately after script exits.
* [ ] Empty Notification Center.
* [ ] Notification Summary enabled.
* [ ] Notification Summary disabled.

---

## Display Configuration Testing

* [ ] Single display.
* [ ] Multiple displays.
* [ ] Different display scaling.
* [ ] Menu bar hidden.
* [ ] Multiple menu bars enabled.
* [ ] MacBook notch.
* [ ] External monitor as primary display.

---

## User Session Edge Cases

* [ ] Locked screen.
* [ ] Sleeping Mac.
* [ ] Wake from sleep with pending notifications.
* [ ] Logged-out user.
* [ ] Fast User Switching.
* [ ] LaunchDaemon with no active GUI user.
* [ ] Accessibility permission revoked.
* [ ] Notification Center process restarted unexpectedly.

---

## Compatibility

Test on:

* [ ] Ventura
* [ ] Sonoma
* [ ] Sequoia
* [ ] Future macOS releases

Document any Accessibility tree differences.

---

## User Experience

* [ ] Quiet mode.
* [ ] Verbose/debug mode.
* [ ] Cleaner logging.
* [ ] Optional exit codes for scripting.
* [ ] Measure execution time and identify performance bottlenecks.

---

## Documentation

* [ ] Document the Accessibility discovery process.
* [ ] Explain why `AXFocused` is used to determine Notification Center visibility.
* [ ] Document tested macOS versions.
* [ ] Add architecture diagram.
* [ ] Add screenshots.
* [ ] Add animated demo GIF.
* [ ] Expand troubleshooting section.

---

## Security

* [ ] Document Accessibility permission requirements.
* [ ] Explain why Accessibility permission is required.
* [ ] Document privacy considerations.

---

## Future Ideas

* [ ] Homebrew formula.
* [ ] Prebuilt universal binary releases.
* [ ] GitHub Actions for automatic builds.
* [ ] Swift Package Manager support.
* [ ] Optional filtering by application (if feasible).
* [ ] Generalize the AX helper routines into a reusable Swift library.
