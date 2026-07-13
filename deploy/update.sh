#!/bin/bash

set -e

APP_DIR=/opt/leidsa-dashboard

echo "Stopping dashboard..."

sudo systemctl stop leidsa.service

cd $APP_DIR

if [ -d .git ]; then
    git pull
fi

sudo systemctl start leidsa.service

echo
echo "Dashboard updated."
