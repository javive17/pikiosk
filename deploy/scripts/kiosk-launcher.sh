#!/bin/bash
# Kiosk launcher - Xvfb + x11vnc pipeline for Chromium on Mali GPU

# Clean up old locks and sockets
rm -f /tmp/.X0-lock /tmp/.X99-lock
rm -rf /tmp/.X11-unix /tmp/.X99-unix

# Start physical X server (HDMI output, just for VNC viewer)
/usr/lib/xorg/Xorg :0 vt1 -keeptty &
XORG_PID=$!

# Start virtual framebuffer for Chromium (portrait mode)
Xvfb :99 -screen 0 1080x1920x24 &
XVFB_PID=$!

# Wait for both displays to be ready
for i in 1 2 3 4 5; do
  sleep 1
  [ -e /tmp/.X11-unix/X0 ] && [ -e /tmp/.X11-unix/X99 ] && break
done

# Start Openbox on physical display
DISPLAY=:0 openbox --startup /usr/lib/aarch64-linux-gnu/openbox-autostart &

# Rotate physical display to portrait (monitor is physically rotated)
DISPLAY=:0 xrandr --output HDMI-1 --rotate right

# Start x11vnc on virtual display (serves :99 on port 5900)
x11vnc -display :99 -forever -shared -nopw -rfbport 5900 -bg 2>/dev/null

# Wait for x11vnc to be ready
for i in 1 2 3 4 5; do
  sleep 1
  ss -tlnp | grep -q 5900 && break
done

# Start Openbox on virtual display
DISPLAY=:99 openbox --startup /usr/lib/aarch64-linux-gnu/openbox-autostart &

# Start VNC viewer on physical display (shows Xvfb content)
DISPLAY=:0 vncviewer localhost:0 -fullscreen -viewonly &
VNCPID=$!

# Chromium restart loop (crash recovery without restarting Xorg/Xvfb)
export DISPLAY=:99
DELAY=1
while true; do
  if ! kill -0 $XORG_PID 2>/dev/null || ! kill -0 $XVFB_PID 2>/dev/null; then
    exit 1
  fi
  /opt/leidsa-dashboard/deploy/scripts/autostart.sh
  sleep $DELAY
  [ $DELAY -lt 10 ] && DELAY=$((DELAY + 1))
done
