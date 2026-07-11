#!/bin/bash

TITLE="Test Persistent Notification"
SUBTITLE="Hammerspoon macro test"
MESSAGE="Press your test hotkey now: ctrl-opt-cmd-X"

osascript <<APPLESCRIPT
display notification "$MESSAGE" with title "$TITLE" subtitle "$SUBTITLE" sound name "Glass"
APPLESCRIPT
