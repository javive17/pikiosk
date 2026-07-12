#!/bin/bash
# Blocking Chromium launcher — runs in foreground, auto-restarts on crash.
# No polling, no fork bomb. Use this directly in openbox autostart.
export DISPLAY=:0
while true; do
    /snap/bin/chromium \
        --kiosk --start-fullscreen --no-first-run \
        --disable-infobars --disable-session-crashed-bubble \
        --disable-features=Translate \
        --overscroll-history-navigation=0 \
        --block-new-web-contents \
        http://localhost:5000
    sleep 5
done
