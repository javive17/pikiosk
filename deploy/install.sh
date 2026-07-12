#!/bin/bash

set -e

APP_USER=$(logname)
APP_HOME=$(eval echo "~$APP_USER")
APP_DIR="/opt/leidsa-dashboard"

echo "======================================="
echo " LEIDSA Dashboard Installer"
echo "======================================="

if [ "$EUID" -ne 0 ]; then
    echo "Run as root:"
    echo "sudo ./install.sh"
    exit 1
fi

apt update
apt full-upgrade -y

apt install -y \
python3 \
python3-pip \
python3-venv \
python3-dev \
build-essential \
gunicorn \
xserver-xorg \
x11-xserver-utils \
xinit \
openbox \
chromium \
unclutter \
curl \
wget \
git \
xrandr \
fonts-dejavu \
fonts-liberation \
fonts-noto

mkdir -p $APP_DIR

echo
echo "Copy your dashboard into:"
echo
echo "   $APP_DIR"
echo
read -p "Press ENTER once copied..."

cd $APP_DIR

python3 -m venv venv

source venv/bin/activate

pip install --upgrade pip wheel

if [ -f requirements.txt ]; then
    pip install -r requirements.txt
else
    pip install \
    flask \
    gunicorn \
    requests
fi

chown -R $APP_USER:$APP_USER $APP_DIR

cp deploy/systemd/leidsa.service /etc/systemd/system/
cp deploy/systemd/kiosk.service /etc/systemd/system/

sed -i "s|__USER__|$APP_USER|g" /etc/systemd/system/leidsa.service
sed -i "s|__HOME__|$APP_HOME|g" /etc/systemd/system/leidsa.service

sed -i "s|__USER__|$APP_USER|g" /etc/systemd/system/kiosk.service
sed -i "s|__HOME__|$APP_HOME|g" /etc/systemd/system/kiosk.service

systemctl daemon-reload

systemctl enable leidsa.service
systemctl enable kiosk.service

systemctl start leidsa.service
systemctl start kiosk.service

echo
echo "Installation Complete."
echo

systemctl status leidsa.service --no-pager
