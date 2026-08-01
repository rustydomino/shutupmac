# ShutUpMac TODO

_Last updated: 2026-07-31_

## Project status

ShutUpMac is functionally feature complete for its current intended scope. The
next major phase is a focused redesign and polish of the macOS GUI rather than
feature expansion.

The target is one coherent management window inspired by established native
menu-bar applications such as Amphetamine: a stable toolbar, clear destination
tabs, restrained controls, and large list-oriented panes for Activity and
Rules.

This project-level TODO is separate from `Packages/notilog/notilog_TODO.md`,
which continues to track lower-level Notilog work.

## Guiding principles

- **STFU:** matching notifications should disappear with minimal friction.
- **KISS:** avoid settings, modes, abstractions, and edge-case machinery unless
  they solve a clear and recurring problem.
- Prefer refinement of existing workflows over new feature breadth.
- Keep ordinary GUI use separate from advanced CLI/configuration workflows.
- Make small, focused edits and build or test after each step.
- Preserve existing behavior while the GUI is reorganized.

## Confirmed GUI direction

Replace the current separate Settings, Activity, and Rules windows with one
unified management window containing four toolbar destinations:

1. **General**
2. **Hot Keys**
3. **Activity**
4. **Rules**

The window should retain a stable overall size. General and Hot Keys may use a
narrow centered content column, while Activity and Rules should use most of the
available width.

About remains a separate small window.

Existing menu commands should continue to provide direct access, but should
open the unified window on the appropriate destination rather than opening
separate windows.

## Confirmed tab responsibilities

### General

- Launch at login.
- Notification logging enable/disable.
- Notification-history privacy controls, including redaction.
- Other genuinely application-wide behavior.

### Hot Keys

- Global hotkey enable/disable.
- Shortcut recorders.
- Brief usage guidance.

### Activity

- Searchable notification history.
- Large list/table as the primary content.
- Refresh and clear-history actions.
- Selection of a notification event.
- **Add Rule from Notification** workflow.
- Clear distinction among:
  - no history;
  - logging disabled;
  - no search results;
  - loading/database failure.

### Rules

- Global **Enable rules-based auto-dismiss** control above the list.
- Large rules list as the primary content.
- Add, edit, delete, enable, and disable ordinary dismissal rules.
- Advanced rules remain visible but clearly read-only.
- Concise rule summaries that preserve the simple mental model:
  **if these conditions match, dismiss the notification**.

## GUI elements to remove

The following controls are no longer appropriate for the finished GUI and
should not be carried into the redesigned tabs:

- Reload `config.json` button.
- Visible/copyable raw `config.json` path.
- CLI installation/path copy-and-paste panel for `shutupmac-cli`.
- General CLI-oriented instructions inside the app.

Advanced users are expected to work through the CLI and configuration files.
CLI installation and usage should instead be documented clearly in
`README.md`.

## GUI redesign roadmap

### Phase 0: Baseline cleanup

- [ ] Remove the duplicated `.onAppear` initialization block in
      `Sources/ShutUpMac/ShutUpMac/SettingsView.swift`.
- [ ] Build the app and confirm Settings behavior is unchanged.
- [ ] Record additional redundancies, but defer cleanup that will naturally
      disappear during the redesign.
- [ ] Keep the current committed tree as the behavioral baseline.

### Phase 1: Unified navigation architecture

- [ ] Introduce a small shared navigation state for the selected destination.
- [ ] Create one unified management-window shell with:
  - General
  - Hot Keys
  - Activity
  - Rules
- [ ] Try native SwiftUI/macOS toolbar-style navigation first.
- [ ] Use a custom toolbar selector only if the native approach cannot provide
      the required layout and window behavior.
- [ ] Keep About separate.
- [ ] Establish one stable default/minimum window size large enough for Activity
      and Rules.
- [ ] Avoid per-tab window resizing that causes visual jumping.

Primary files likely involved:

- `Sources/ShutUpMac/ShutUpMac/ShutUpMacApp.swift`
- a new root/navigation view if needed
- existing Settings, Activity, and Rules views

### Phase 2: Split the current Settings view

- [ ] Extract General content from the current monolithic `SettingsView`.
- [ ] Extract Hot Keys content into its own view.
- [ ] Preserve preference storage and runtime callbacks unchanged.
- [ ] Omit the deleted config reload/path controls.
- [ ] Omit the deleted CLI installation/path panel.
- [ ] Keep this phase primarily a code move, not a behavioral rewrite.

Possible resulting structure:

```text
ManagementRootView
├── GeneralSettingsView
├── HotKeySettingsView
├── ActivityView
└── RulesView
```

### Phase 3: Embed existing Activity and Rules behavior

- [ ] Place the existing Activity view in the Activity destination.
- [ ] Place the existing Rules view in the Rules destination.
- [ ] Preserve current search, sorting, loading, editing, saving, and runtime
      behavior before visual redesign.
- [ ] Route existing menu commands to the unified window:
  - Settings opens General.
  - Activity opens Activity.
  - Rules opens Rules.
- [ ] Confirm only one management window is used.
- [ ] Verify window activation and focus when the app is menu-bar-only.

Milestone acceptance criteria:

- One stable window.
- Four working destinations.
- Existing functionality remains available.
- Existing direct menu access still works.
- No Activity or Rules behavior regression.

### Phase 4: Redesign the Rules destination

Use the broad layout rhythm of Amphetamine's Trigger pane without copying it
control-for-control:

```text
Global rules control
        ↓
Large rules list
        ↓
Compact action bar
        ↓
Small status/help text
```

- [ ] Place **Enable rules-based auto-dismiss** above the list.
- [ ] Make the rules list the dominant visual element.
- [ ] Improve row hierarchy:
  - enabled state;
  - rule name;
  - concise match summary;
  - ordinary versus advanced/read-only status.
- [ ] Keep advanced rules visibly locked/read-only.
- [ ] Use compact Add and Delete controls.
- [ ] Support clear Edit behavior through double-click, button, or context menu.
- [ ] Improve the selected-row appearance.
- [ ] Improve the no-rules empty state.
- [ ] Refine editor spacing, labels, and validation feedback.
- [ ] Preserve the one-action GUI model: matching rules dismiss notifications.
- [ ] Do not expose script actions or disappearance-event editing.

### Phase 5: Redesign the Activity destination

Use the same overall geometry as Rules:

```text
Search/filter control
        ↓
Large activity list
        ↓
Compact action bar
        ↓
Small status/help text
```

- [ ] Make search prominent but visually restrained.
- [ ] Make the event list the dominant visual element.
- [ ] Improve title/subtitle/body hierarchy and row density.
- [ ] Keep duplicated application-name cleanup where appropriate.
- [ ] Review timestamp placement and formatting.
- [ ] Align Refresh, Clear History, and Add Rule actions consistently.
- [ ] Make **Add Rule from Notification** dependent on a selected event.
- [ ] Keep destructive history clearing visually secondary and confirmed.
- [ ] Show useful footer/status information such as displayed record count or
      filtering state.
- [ ] Preserve the Spotlight-style search model.
- [ ] Do not add Finder-style multi-column complexity merely for its own sake.

### Phase 6: Activity-to-Rules workflow

Implement the contextual workflow only after the destination layouts and Rules
editor are stable.

Expected flow:

1. User selects an Activity event.
2. User chooses **Add Rule from Notification**.
3. The app creates an unsaved rule draft.
4. The unified window switches to Rules.
5. The Rules editor opens with appropriate fields prefilled.
6. The user reviews, changes, and explicitly saves the rule.

Implementation constraints:

- [ ] Share only the minimal navigation/draft state needed by Activity and
      Rules.
- [ ] Do not save a rule automatically.
- [ ] Do not couple Activity directly to the configuration store.
- [ ] Do not create rules that match literal `[REDACTED]` values.
- [ ] Define sensible behavior when the source event contains redacted or empty
      fields.
- [ ] Preserve the existing ordinary-rule validation and atomic save behavior.

Open UX decision before implementation:

- Decide which notification fields should be preselected as rule conditions.
  Exact matching of app, title, subtitle, and body together is likely too
  specific. A likely starting point is a suggested rule name plus an exact app
  condition, with notification text available for the user to select from.

### Phase 7: General and Hot Keys visual polish

- [ ] Use a compact centered form layout inside the wider unified window.
- [ ] Standardize section spacing, labels, captions, and control alignment.
- [ ] Keep explanatory text short and secondary.
- [ ] Ensure preference changes do not cause unnecessary layout movement or
      flashing.
- [ ] Review disabled-state behavior for privacy controls.
- [ ] Keep the tabs simpler than Activity and Rules rather than filling space.

### Phase 8: Accessibility and final regression work

- [ ] Add or review accessibility labels and help text.
- [ ] Verify keyboard navigation and focus order.
- [ ] Verify toolbar destinations can be reached without a mouse.
- [ ] Verify common actions have appropriate keyboard shortcuts where useful.
- [ ] Check light and dark appearances.
- [ ] Check reasonable window sizing on common Mac display sizes.
- [ ] Verify window restoration and destination selection behavior.
- [ ] Run the full Notilog package test suite.
- [ ] Run the ShutUpMac Xcode tests.
- [ ] Complete focused manual regression testing for all four destinations.
- [ ] Remove obsolete scene/window-opening code after the unified window is
      proven stable.

## Rules and Activity shared visual language

Rules and Activity should feel related without requiring a generalized UI
framework.

Prefer consistent:

- outer padding;
- list/table height and borders;
- header spacing;
- action-bar alignment;
- selected-row treatment;
- empty-state presentation;
- secondary footer/help text.

Extract shared components or constants only after real duplication is visible.
Do not build a design system in advance.

## Cleanup policy during the redesign

Perform cleanup immediately when it is:

- clearly redundant;
- behavior-independent;
- unlikely to be invalidated by the redesign.

Defer cleanup when the affected code will soon be removed or relocated.

Examples:

- Remove the duplicate Settings `.onAppear` now.
- Resolve Activity's current default/minimum-width mismatch as part of the
  unified-window sizing work rather than patching both old and new designs.
- Do not polish spacing in UI sections already scheduled for deletion.

## Documentation work

- [ ] Expand `README.md` CLI documentation after the GUI redesign stabilizes.
- [ ] Clearly distinguish:
  - the ShutUpMac menu-bar app;
  - `shutupmac-cli` imperative dismissal commands;
  - `notilog-cli` monitoring, logging, and automation modes;
  - advanced `config.json` rule editing.
- [ ] Document CLI installation and executable paths outside the GUI.
- [ ] Include representative examples for ordinary operations and advanced
      configuration.
- [ ] Update README screenshots after the new unified GUI is complete.
- [ ] Update `CHANGELOG.md` when the redesign is ready for release.

## Explicitly out of scope unless reopened

- Global auto-dismiss-all / nuclear option.
- Per-rule dismissal delay.
- Script-action editing in the GUI.
- Disappearance-event editing in the GUI.
- Broad advanced field/event builders.
- Complex stack inspection or stack-skipping behavior.
- Finder-style Activity sorting/filter complexity without a demonstrated need.
- Runtime config reload controls in the GUI.
- CLI installation/path panels in the GUI.

## Accepted platform limitation

When macOS exposes multiple notifications from one application as a collapsed
Accessibility notification stack, the available action may operate like Clear
All for that application's stack. A rule matching one notification can therefore
clear other notifications in the same stack.

This remains an accepted macOS Accessibility limitation. Activity/database
logging reduces its practical impact. Do not add complex stack-skipping logic
unless this decision is explicitly reopened.

## Working style

For each implementation step:

1. Explain the purpose of the change.
2. Provide the file path and approximate line numbers.
3. Include enough surrounding code to locate the edit.
4. Make one focused change at a time.
5. Build or run the narrowest relevant test.
6. Visually or manually verify user-facing behavior.
7. Commit at meaningful, stable milestones.

## Next action

- [ ] Remove the duplicate `.onAppear` block from `SettingsView.swift`.
- [ ] Build and verify the current Settings window.
- [ ] Begin the unified four-destination window shell.
