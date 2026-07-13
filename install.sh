#!/bin/bash
set -euo pipefail

REPO_URL=${REPO_URL:-https://github.com/javive17/pikiosk.git}
INSTALL_DIR=/opt/leidsa-dashboard
USERNAME=${SUDO_USER:-orangepi}
USER_HOME=$(eval echo ~$USERNAME)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERR]${NC} $1"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi

info "=== PI KIOSK INSTALLER ==="
info "User: $USERNAME | Target: $INSTALL_DIR"

if [ -d "$INSTALL_DIR/.git" ]; then
    info "Repo already cloned, updating..."
    cd "$INSTALL_DIR" && git pull
else
    if [ -d "$INSTALL_DIR" ]; then
        warn "$INSTALL_DIR exists but not a git repo, backing up..."
        mv "$INSTALL_DIR" "${INSTALL_DIR}.bak.$(date +%s)"
    fi
    info "Cloning repo from $REPO_URL ..."
    git clone "$REPO_URL" "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

info "Installing system packages..."
apt-get update -qq
apt-get install -y -qq \
    python3 python3-pip python3-venv python3-dev \
    xserver-xorg x11-xserver-utils xinit openbox \
    unclutter curl wget git \
    fonts-dejavu fonts-liberation fonts-noto

if ! command -v chromium &>/dev/null; then
    if command -v snapctl &>/dev/null; then
        info "Installing Chromium via snap..."
        snap install chromium
    else
        warn "Snap not available, skipping Chromium install"
        warn "Install Chromium manually after setup"
    fi
fi

info "Creating Python virtual environment..."
python3 -m venv "$INSTALL_DIR/venv"
source "$INSTALL_DIR/venv/bin/activate"
pip install --upgrade pip wheel -q
pip install flask gunicorn requests -q

info "Creating deploy scripts..."
cat > "$INSTALL_DIR/deploy/scripts/rotate-display.sh" << 'SCRIPT'
#!/bin/bash
export DISPLAY=:0
OUTPUT=$(xrandr | grep " connected" | head -1 | cut -d" " -f1)
[ -n "$OUTPUT" ] && xrandr --output "$OUTPUT" --rotate right
SCRIPT

cat > "$INSTALL_DIR/deploy/scripts/disable-blanking.sh" << 'SCRIPT'
#!/bin/bash
export DISPLAY=:0
xset s off
xset -dpms
xset s noblank
SCRIPT

cat > "$INSTALL_DIR/deploy/scripts/watchdog.sh" << 'SCRIPT'
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
SCRIPT

cat > "$INSTALL_DIR/deploy/scripts/healthcheck.sh" << 'SCRIPT'
#!/bin/bash
if ! curl -sf http://localhost:5000 > /dev/null 2>&1; then
    /usr/bin/systemctl restart leidsa.service
fi
SCRIPT

chmod +x "$INSTALL_DIR/deploy/scripts/"*.sh

info "Installing systemd services..."
cp "$INSTALL_DIR/deploy/systemd/leidsa.service" /etc/systemd/system/
sed -i "s/__USER__/$USERNAME/g" /etc/systemd/system/leidsa.service
cp "$INSTALL_DIR/deploy/systemd/fallback-ip.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable leidsa.service
systemctl enable fallback-ip.service

info "Configuring autologin..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << UNIT
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear %I \$TERM
UNIT

info "Configuring user autostart..."
mkdir -p "$USER_HOME/.config/openbox"

cat > "$USER_HOME/.bash_profile" << PROFILE
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
    startx
fi
PROFILE

cat > "$USER_HOME/.xinitrc" << XINIT
#!/bin/bash
exec openbox-session
XINIT
chmod +x "$USER_HOME/.xinitrc"

cat > "$USER_HOME/.config/openbox/autostart" << OBAUTOSTART
#!/bin/bash
$INSTALL_DIR/deploy/scripts/disable-blanking.sh &
$INSTALL_DIR/deploy/scripts/rotate-display.sh &
unclutter -idle 0.5 &
sleep 5
exec $INSTALL_DIR/deploy/scripts/watchdog.sh
OBAUTOSTART
chmod +x "$USER_HOME/.config/openbox/autostart"
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.bash_profile" "$USER_HOME/.xinitrc" "$USER_HOME/.config"

info "Setting kernel panic reboot..."
cat >> /etc/sysctl.conf << SYSCTL
kernel.panic=10
kernel.panic_on_oops=1
SYSCTL
sysctl -p

info "Creating logrotate config..."
cat > /etc/logrotate.d/leidsa-dashboard << LOGR
$INSTALL_DIR/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGR

info "Creating cron jobs..."
(crontab -u "$USERNAME" -l 2>/dev/null; echo "0 4 * * * /sbin/reboot") | crontab -u "$USERNAME" -
(crontab -u "$USERNAME" -l 2>/dev/null; echo "*/5 * * * * $INSTALL_DIR/deploy/scripts/healthcheck.sh") | crontab -u "$USERNAME" -

info "Creating helper symlinks..."
mkdir -p /usr/local/bin
ln -sf "$INSTALL_DIR/deploy/scripts/dashboard-status" /usr/local/bin/dashboard-status 2>/dev/null || true
ln -sf "$INSTALL_DIR/deploy/update.sh" /usr/local/bin/update-dashboard 2>/dev/null || true
ln -sf "$INSTALL_DIR/deploy/backup.sh" /usr/local/bin/backup-dashboard 2>/dev/null || true

mkdir -p "$INSTALL_DIR/logs"
chown -R "$USERNAME:$USERNAME" "$INSTALL_DIR"

info "Starting backend service..."
systemctl start leidsa.service

info ""
info "=== INSTALLATION COMPLETE ==="
info "The kiosk will start automatically on next reboot."
info ""
echo -e "  ${YELLOW}Reboot now?${NC} [y/N] \c"
read -r REBOOT
if [ "$REBOOT" = "y" ] || [ "$REBOOT" = "Y" ]; then
    info "Rebooting..."
    reboot
fi
