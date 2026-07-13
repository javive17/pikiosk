#!/bin/bash
# Blocking Firefox kiosk launcher
# Runs in foreground — openbox waits on this.
# No polling, no fork bomb.
export DISPLAY=:0

PROFILE=/opt/leidsa-dashboard/firefox-profile
URL=http://localhost:5000

# Kill stale Firefox processes
pkill -9 firefox 2>/dev/null || true
sleep 2

# Pre-initialize profile to skip first-run wizard
if [ ! -f "$PROFILE/.initialized" ]; then
    echo "Pre-initializing Firefox profile..."
    timeout 15 firefox --headless --no-remote --profile "$PROFILE" --first-startup about:blank 2>/dev/null || true
    pkill -9 firefox 2>/dev/null || true
    touch "$PROFILE/.initialized"
    sleep 2
fi

while true; do
    firefox \
        --kiosk \
        --no-remote \
        --new-instance \
        --profile "$PROFILE" \
        "$URL"
    sleep 5
done
