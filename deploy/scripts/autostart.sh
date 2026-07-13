#!/bin/bash
# Direct kiosk launcher for use with systemd kiosk.service
# Runs in foreground so systemd can track and restart it
export DISPLAY=:0

# Ensure X is ready
sleep 3

# Kill stale Firefox processes (avoid multiple instances)
pkill -9 firefox 2>/dev/null || true
sleep 1

exec firefox \
    --kiosk \
    --no-remote \
    --new-instance \
    --profile /opt/leidsa-dashboard/firefox-profile \
    http://localhost:5000
