#!/usr/bin/env bash
# Remove PrivyLock's per-user login agent without removing the app itself.

set -euo pipefail

LABEL="com.applock.helper"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

/bin/launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
if [[ -f "$PLIST" ]]; then
    rm -f "$PLIST"
    echo "Removed $PLIST"
else
    echo "No PrivyLock login agent found"
fi
