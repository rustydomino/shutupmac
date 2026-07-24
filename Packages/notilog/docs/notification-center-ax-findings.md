# Notification Center AX Findings

Date: 2026-07-18 / 2026-07-19

Context: these notes document what macOS Notification Center exposes through the Accessibility API while inspecting live banners, opened Notification Center items, and hidden/stored notifications. The goal is to guide future notilog and ShutUpMac scanner/dismissal work.

## Executive summary

macOS notifications are exposed through AX, but the shape depends on UI state. `AXNotificationCenterBanner` does not always mean only a live banner, and `AXNotificationCenterBannerStack` does not always mean multiple notifications in a user-visible stack. The ancestor path is important.

The most useful discriminator found so far:

```text
AXNotificationListItems present in ancestor path
  => item is inside the opened Notification Center list

AXNotificationListItems absent
  => item is more likely a live transient banner/alert outside the list
```

A visible relative timestamp such as `2m ago` is exposed in at least one full-tree dump as an unlabeled `AXStaticText` child with an `AXValue`, but it is UI text, not a durable timestamp.

## Observed notification shapes

### 1. Live banner

Observed subrole:

```text
AXNotificationCenterBanner
```

Observed fields:

```text
role: AXGroup
subrole: AXNotificationCenterBanner
identifier: UUID-like AX identifier
desc: App, Title, Body
actions: AXPress, Show Details, Close
children: title/body static text nodes in full dumps
```

Example action set:

```text
AXActions: AXPress, Name:Close, Name:Show Details
```

Implication for ShutUpMac: live banners can likely be dismissed by locating the `AXNotificationCenterBanner` with the matching identifier and performing the custom `Close` action.

Implication for notilog: add `AXNotificationCenterBanner` to the scanner's notification candidate subroles.

## 2. Notification Center list item: single stored item

A single visible item inside opened Notification Center was observed under:

```text
AXScrollArea
  AXGroup id=AXNotificationListItems
    AXGroup subrole=AXNotificationCenterBanner
```

Important correction: a single stored Notification Center item may still use:

```text
AXNotificationCenterBanner
```

So `AXNotificationCenterBanner` alone is not enough to distinguish live vs stored. The parent/ancestor path matters.

Observed fields:

```text
role: AXGroup
subrole: AXNotificationCenterBanner
identifier: UUID-like AX identifier
desc: App, Title, Body
actions: AXPress, Close, Show Details
children:
  AXStaticText id=title value=...
  AXStaticText id=body value=...
  AXStaticText value=2m ago
```

The relative timestamp was exposed as a third child:

```text
AXStaticText value=2m ago
AXValue: 2m ago
```

It had no `AXIdentifier`; its location was on the right side of the notification card.

## 3. Notification Center list item: stacked/grouped stored item

Observed path:

```text
AXScrollArea
  AXGroup id=AXNotificationListItems
    AXGroup subrole=AXNotificationCenterBannerStack
```

Observed fields:

```text
role: AXGroup
subrole: AXNotificationCenterBannerStack
identifier: UUID-like AX identifier
desc: App, Title, Body, stacked
actions: AXPress, Clear All, Show Details
children:
  AXStaticText id=title value=...
  AXStaticText id=body value=...
```

In the stack full dump, no timestamp child was found inside the stack candidate subtree. Earlier filtered dumps did show unlabeled right-side static text nodes near stack cards, but the filtered dump did not include their values. More testing is needed before assuming stack timestamps are always available.

## Metadata observed

Reliable or semi-reliable fields found through AX:

```text
AXRole
AXSubrole
AXIdentifier
AXDescription / AXAttributedDescription
AXFrame
AXPosition
AXSize
AXActivationPoint
AXActions / AXCustom action names
AXChildrenInNavigationOrder
AXStaticText child AXIdentifier values: title, subtitle, body, header
AXStaticText child AXValue values: title/body text and sometimes relative age text
```

Useful notification-level values:

```text
subrole
AX identifier
combined description
visible title
visible subtitle/header when present
visible body
relative display age, e.g. 2m ago, when exposed
available actions: Close, Clear All, Dismiss, Snooze, Show Details
screen frame / position
whether ancestor path contains AXNotificationListItems
```

## Metadata not found

These were not observed as clean AX fields in the dumps:

```text
absolute delivery timestamp
source app bundle identifier
notification category identifier
thread identifier
UNNotification userInfo payload
original delivery style setting, e.g. banner vs alert
whether a stored item was originally a temporary banner
stable global notification ID
```

The UUID-like `AXIdentifier` should be treated as a runtime AX identity, not as a durable notification ID.

## Timestamp finding

The visual timestamp can be exposed, but as UI text.

Observed example:

```text
AXStaticText value=2m ago
AXValue: 2m ago
```

Parsing recommendation:

```swift
let relativeAgePattern = #"^(now|\d+\s*[mhd]\s+ago|\d+\s+(min|mins|minute|minutes|hour|hours|day|days)\s+ago|Yesterday|Today)$"#
```

Caveats:

- This is localized UI text.
- It is relative, not absolute.
- It changes over time.
- It should be stored as `displayAge` or `relativeAgeText`, not as the event timestamp.
- notilog's own observation timestamp should remain the durable timestamp.

Suggested model field:

```swift
public let displayAge: String?
```

or more explicit:

```swift
public let relativeAgeText: String?
```

## Recommended notilog scanner logic

Candidate subroles:

```swift
let notificationSubroles = Set([
    "AXNotificationCenterAlert",
    "AXNotificationCenterAlertStack",
    "AXNotificationCenterBanner",
    "AXNotificationCenterBannerStack"
])
```

Then classify by both subrole and ancestry:

```text
ancestor contains AXNotificationListItems
  => stored/list item inside opened Notification Center

ancestor does not contain AXNotificationListItems
  => live onscreen notification candidate
```

Suggested presentation enum:

```swift
public enum NotificationPresentation: String, Codable {
    case liveAlert
    case liveBanner
    case liveStack
    case notificationCenterItem
    case notificationCenterStack
    case unknown
}
```

Suggested parsing rules:

1. Prefer child `AXStaticText` values.
2. Map child `AXIdentifier` values:

```text
title    -> notification title
subtitle -> notification subtitle
body     -> notification body
header   -> app/header-ish field for some apps
nil      -> possible relative display age or other accessory text
```

3. For unlabeled `AXStaticText`, check whether `AXValue` looks time-like. Store it as `relativeAgeText`.
4. Fall back to `AXDescription` / `AXAttributedDescription` when child text is missing.
5. Strip trailing `, stacked` or ` stacked` from combined descriptions before parsing app/title/body.
6. Treat the first comma-separated field in `AXDescription` as app/display source only as a fallback. Some notification bodies may contain commas.

## Recommended ShutUpMac dismissal logic

Use the `subrole|identifier` key format already discovered:

```text
AXNotificationCenterBanner|<AXIdentifier>
AXNotificationCenterBannerStack|<AXIdentifier>
AXNotificationCenterAlert|<AXIdentifier>
```

For dismissal:

```text
AXNotificationCenterBanner
  prefer custom action: Close

AXNotificationCenterAlert
  use existing alert close/dismiss path

AXNotificationCenterBannerStack
  be cautious: actions may include Clear All, Dismiss, Snooze, Show Details
  do not blindly perform Clear All unless the user intentionally wants to clear the stored group/list item
```

## Open questions

- Are live persistent alert notifications still always `AXNotificationCenterAlert` on this macOS version?
- Does `AXNotificationCenterAlertStack` still appear, and under what conditions?
- Do stack/grouped Notification Center items expose timestamp text in a different subtree or only in some apps/UI states?
- Does hovering, focusing, or expanding a card change which AX children are exposed?
- Is the relative age string localized according to system language/region?
- Do actions vary by app and notification category enough that they need to be stored per snapshot?

## Practical implementation priority

1. Add `AXNotificationCenterBanner` to notilog live scanning.
2. Add child `AXStaticText` value extraction, not just title/description extraction.
3. Add an `ancestorPath` or `isInNotificationCenterList` classification check.
4. Add optional `relativeAgeText` capture for unlabeled time-like static text.
5. Keep durable event time as notilog's own observation timestamp.
6. Update ShutUpMac to support `AXNotificationCenterBanner|...` keys and perform the `Close` action.
7. Treat `AXNotificationCenterBannerStack` as a separate stored/list item mode, not as the primary live dismissal path.

## Source dump files used

```text
ax-dump-no-banner.log
ax-dump-no-notifications.log
ax-dump-nc-empty.log
ax-dump-nc-hidden.log
ax-dump-nc-single.log
nc-hidden-single.log
nc-hidden-stack.log
nc-hidden-single-all.log
nc-hidden-stack-all.log
```

