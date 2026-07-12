#!/bin/bash
# This file goes in ~/.config/openbox/autostart
/opt/leidsa-dashboard/deploy/scripts/disable-blanking.sh &
/opt/leidsa-dashboard/deploy/scripts/rotate-display.sh &
unclutter -idle 0.5 &
sleep 5
exec /opt/leidsa-dashboard/deploy/scripts/watchdog.sh
