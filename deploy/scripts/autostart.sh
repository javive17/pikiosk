#!/bin/bash
export DISPLAY=:0
xset s off
xset -dpms
xset s noblank
unclutter -idle 0.5 &
OUTPUT=$(xrandr | grep " connected" | head -1 | cut -d" " -f1)
[ -n "$OUTPUT" ] && xrandr --output "$OUTPUT" --rotate right
sleep 2
/snap/bin/chromium \
--kiosk \
--start-fullscreen \
--no-first-run \
--disable-infobars \
--disable-session-crashed-bubble \
--disable-features=Translate \
--overscroll-history-navigation=0 \
--block-new-web-contents \
http://localhost:5000
