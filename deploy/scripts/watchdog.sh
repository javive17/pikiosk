#!/bin/bash
# Blocking Firefox kiosk launcher
# Runs in foreground — openbox waits on this.
# No polling, no fork bomb.
export DISPLAY=:0

# Kill stale Firefox processes (avoid multiple instances)
pkill -9 firefox 2>/dev/null || true
sleep 2

while true; do
    firefox \
        --kiosk \
        --no-remote \
        --new-instance \
        --profile /opt/leidsa-dashboard/firefox-profile \
        http://localhost:5000
    sleep 5
done
