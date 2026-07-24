# notilog Notification Center AX Findings and Design Notes

Date: 2026-07-18 / 2026-07-19

This document captures the recent Accessibility (AX) findings around macOS Notification Center, plus the proposed notilog design direction for live notification logging and optional Notification Center sweeps.

## Executive summary

notilog is in a good place for live desktop notifications. The default mode should be a continuous live watcher that polls visible desktop notifications and logs alerts/banners as they appear.

A second optional mode should periodically open Notification Center, inspect stored/hidden notifications, expand stacks, and record whatever metadata is available there. This mode is especially useful because Notification Center exposes a visible relative age label such as `2m ago` for at least some stored notifications.

The key product distinction:

```text
Live watcher:
  catches notifications when they are visible on the desktop

Notification Center sweep:
  catches notifications that remain stored/hidden in Notification Center
```

## AX taxonomy discovered so far

### Live desktop alert

Persistent alert-style notifications appear as:

```text
AXGroup
subrole: AXNotificationCenterAlert
```

Observed fields include:

```text
AXIdentifier
AXDescription / AXAttributedDescription
AXFrame / AXPosition / AXSize
AXActions: AXPress, Close, Show Details
AXStaticText id=title value=...
AXStaticText id=body value=...
```

### Live desktop banner

Temporary banner-style notifications appear as:

```text
AXGroup
subrole: AXNotificationCenterBanner
```

Observed fields include:

```text
AXIdentifier
AXDescription / AXAttributedDescription
AXFrame / AXPosition / AXSize
AXActions: AXPress, Close, Show Details
AXStaticText id=title value=...
AXStaticText id=body value=...
```

Banners last for roughly five seconds on the desktop, so a 1 Hz poll loop should be sufficient for the default live watcher.

### Stored Notification Center item

Stored/hidden Notification Center items live under an ancestor/container with:

```text
AXIdentifier: AXNotificationListItems
```

Important finding: subrole alone is not enough to decide whether an item is live or stored. The more reliable signal is the ancestor path. If the notification-looking element is under `AXNotificationListItems`, treat it as a stored Notification Center item.

Stored items may appear as:

```text
AXNotificationCenterBanner
AXNotificationCenterBannerStack
```

A single stored item can appear as `AXNotificationCenterBanner`. A grouped/stacked stored item can appear as `AXNotificationCenterBannerStack`.

## Timestamp / age label finding

The visual relative timestamp, such as:

```text
2m ago
```

is exposed in the full AX tree for at least some stored Notification Center items.

In the full dump of a single stored Notification Center item, the notification had three children:

```text
AXStaticText id=title value=ShutUpMac Test Notification
AXStaticText id=body value=This is a test notification for ShutUpMac.
AXStaticText value=2m ago
```

The age label child:

```text
role: AXStaticText
identifier: nil
AXValue: 2m ago
```

It sits visually on the right side of the notification card. Since it has no identifier, code should detect it by role/value/position/pattern rather than by `AXIdentifier`.

This is not a durable absolute timestamp. It is localized UI text. Store it as evidence and convert it only into a best-effort estimate.

Recommended fields:

```text
observed_at
  Real time when notilog saw the item.

display_age_text
  Raw AX UI text, for example "2m ago".

estimated_delivered_at
  Best-effort inferred timestamp, for example observed_at - 2 minutes.

estimated_timestamp_source
  Example values:
    observed_at
    notification_center_display_age
    unavailable

estimated_timestamp_confidence
  Example values:
    medium
    low
    none
```

Suggested policy:

```text
Live desktop notifications:
  observed_at = Date()
  display_age_text = NULL
  estimated_delivered_at = observed_at
  estimated_timestamp_source = observed_at
  estimated_timestamp_confidence = medium

Notification Center sweep with age text:
  observed_at = Date()
  display_age_text = raw AXValue, e.g. "2m ago"
  estimated_delivered_at = observed_at minus parsed relative age
  estimated_timestamp_source = notification_center_display_age
  estimated_timestamp_confidence = low

Notification Center sweep without age text:
  observed_at = Date()
  display_age_text = NULL
  estimated_delivered_at = NULL or observed_at, depending on query needs
  estimated_timestamp_source = unavailable
  estimated_timestamp_confidence = none
```

## axIdentifier vs key

### axIdentifier

`AXIdentifier` appears to identify the notification instance itself.

Examples look like:

```text
AE12207F-FDF0-47F3-B89B-17DA3B57BBC9
```

Recent tests showed that `AXIdentifier` survived:

```text
sleep/wake
reboot
```

In the reboot test, Notification Center had a new process ID after reboot, but the notification still had the same `AXIdentifier`. That strongly suggests the identifier is tied to macOS's stored notification record, not just an in-memory AX object.

Important wording: this is empirical behavior, not a documented Apple API contract.

### key

notilog currently builds a runtime key as:

```text
subrole + "|" + axIdentifier
```

Example:

```text
AXNotificationCenterAlert|AE12207F-FDF0-47F3-B89B-17DA3B57BBC9
```

The key is useful for targeting the current AX object, especially for dismissal through ShutUpMac.

### ELI5 model

```text
axIdentifier:
  the notification's name tag / license plate

subrole:
  the notification's current costume / presentation state

key:
  the notification's current address in the AX world
```

For correlation and deduplication, prefer `axIdentifier`.

For acting on the current visible object, prefer `key`.

## Proposed notilog scan modes

## Mode 1: live desktop watcher

This should be the default behavior.

Responsibilities:

```text
poll continuously, probably 1 Hz
scan for visible desktop notifications
log appeared/disappeared events
run automation rules when enabled
```

Notification subroles to include:

```text
AXNotificationCenterAlert
AXNotificationCenterBanner
```

Fields to capture:

```text
observed_at
event_type
source_context = live_desktop
ax_identifier
subrole
key
app
title
subtitle
body
frame_x
frame_y
frame_width
frame_height
actions
```

Notes:

- Banners should be captured with 1 Hz polling because they remain on screen for several seconds.
- Alerts are persistent and easier to capture.
- `AXNotificationCenterBannerStack` should not be treated as a live desktop notification by default.

## Mode 2: optional Notification Center sweep

This should be optional and user-configured.

Possible CLI shapes:

```bash
notilog-cli sweep-notification-center
```

or:

```bash
notilog-cli watch --sweep-notification-center --sweep-interval 3h
```

Responsibilities:

```text
at a user-configured interval:
  open Notification Center
  scan stored notifications under AXNotificationListItems
  expand stacks if present
  rescan after expansion
  capture title/body/app/identifier/subrole/display age
  store snapshot/results
  close Notification Center if not previously open
```

Conservative behavior:

- Avoid destructive actions such as `Clear`, `Clear All`, `Dismiss`, or `Close` during sweep mode.
- It is acceptable to open Notification Center and expand UI for inspection.
- It should avoid changing notification state unless the user explicitly requests cleanup/dismissal behavior.

## Stack expansion plan

A stored stack may expose actions like:

```text
AXPress
Show Details
Clear All
Dismiss
Snooze
```

Sweep mode should prefer non-destructive expansion actions:

```text
Show Details
AXPress, only if testing confirms it expands rather than clears/dismisses
```

Algorithm sketch:

```text
open Notification Center
scan AXNotificationListItems
for each stored notification candidate:
  if candidate appears stacked/grouped:
    if it has Show Details:
      perform Show Details
      wait briefly
    else if AXPress is known safe for this shape:
      perform AXPress
      wait briefly
rescan AXNotificationListItems
record expanded child notifications if exposed
```

Need careful manual testing before enabling stack expansion by default.

## Suggested database evolution

Current notilog tables can be extended gradually. A future event/storage model should preserve both observed facts and inferred estimates.

Suggested additional columns or equivalent model fields:

```text
ax_identifier TEXT
subrole TEXT
source_context TEXT
observed_at TEXT

display_age_text TEXT
estimated_delivered_at TEXT
estimated_timestamp_source TEXT
estimated_timestamp_confidence TEXT

frame_x REAL
frame_y REAL
frame_width REAL
frame_height REAL

actions TEXT
parent_ax_identifier TEXT
is_stacked INTEGER
```

Possible `source_context` values:

```text
live_desktop
notification_center_sweep
```

Possible `estimated_timestamp_source` values:

```text
observed_at
notification_center_display_age
unavailable
```

Possible `estimated_timestamp_confidence` values:

```text
medium
low
none
```

## Deduplication and correlation

Use `axIdentifier` as the primary correlation signal when available.

Useful identity levels:

```text
current_ax_key:
  subrole|axIdentifier
  best for current targeting/dismissal

ax_identifier:
  best for correlating one notification across state changes, sleep/wake, and reboot

content fingerprint:
  fallback when AXIdentifier is unavailable
  e.g. app + title + subtitle + body
```

Recommended approach:

```text
If axIdentifier matches an existing active/stored record:
  update the existing logical notification record
  append a new observation/event if source_context or subrole changed

If axIdentifier is new:
  create a new logical notification record
```

Possible event types later:

```text
appeared
hidden_in_notification_center
disappeared
reappeared_after_reboot
seen_in_sweep
expanded_from_stack
```

Do not overcommit to these names yet; they are design notes.

## Implementation order

### Step 1: Add live banner logging

Add `AXNotificationCenterBanner` to the live scanner.

Ensure parser captures:

```text
AXStaticText id=title
AXStaticText id=body
AXDescription fallback
AXIdentifier
subrole
frame
actions
```

### Step 2: Store axIdentifier/subrole separately

Keep `key`, but make sure the database/model also stores:

```text
ax_identifier
subrole
```

This avoids treating `key` as the only identity.

### Step 3: Add timestamp estimate fields

Add schema/model support for:

```text
display_age_text
estimated_delivered_at
estimated_timestamp_source
estimated_timestamp_confidence
```

Live watcher can initially populate these conservatively.

### Step 4: Prototype Notification Center sweep command

Add an explicit command first rather than making it recurring immediately:

```bash
notilog-cli sweep-notification-center
```

This gives a safe manual test loop.

### Step 5: Add stack expansion experiments

Only after manual sweep works:

```text
identify stacks
perform Show Details
rescan
record expanded children
```

### Step 6: Add periodic sweep scheduling

Once manual sweep is reliable, add recurrence:

```bash
notilog-cli watch --sweep-notification-center --sweep-interval 3h
```

or defer recurrence to LaunchAgent configuration.

## Open questions

- Does `AXIdentifier` survive reboot for banners and stored Notification Center items, not just persistent alerts?
- Does `AXIdentifier` remain stable when a live banner becomes a stored Notification Center item?
- Is `Show Details` always safe and non-destructive for stacks?
- Does stack expansion expose individual child notification identifiers?
- Is the relative timestamp always an unlabeled `AXStaticText`, or does it vary by app/style/macOS version?
- How should localized relative time strings be parsed?
- Should notilog parse `2m ago` into an estimate immediately, or store raw text first and parse later?

## Current recommendation

Proceed with live desktop logging first:

```text
AXNotificationCenterAlert
AXNotificationCenterBanner
```

Then add a manual Notification Center sweep command as a separate feature. The sweep should prioritize capturing stored notifications and their visible relative age labels, while preserving raw evidence and marking timestamp estimates as low confidence.

