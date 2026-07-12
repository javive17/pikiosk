#!/bin/bash

while true
do

if ! pgrep chromium >/dev/null
then
    systemctl restart kiosk.service
fi

sleep 20

done
