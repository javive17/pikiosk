#!/bin/bash

systemctl stop kiosk.service

systemctl stop leidsa.service

rm -rf /opt/leidsa-dashboard/venv

python3 -m venv /opt/leidsa-dashboard/venv

source /opt/leidsa-dashboard/venv/bin/activate

pip install --upgrade pip

pip install -r /opt/leidsa-dashboard/requirements.txt

systemctl restart leidsa.service

systemctl restart kiosk.service

echo

echo Factory reset complete.
