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

info "=== PI KIOSK INSTALLER (Firefox) ==="
info "User: $USERNAME | Target: $INSTALL_DIR"

# --------------------------------------------------
# 1. Clone / update repo
# --------------------------------------------------
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

# --------------------------------------------------
# 2. System packages (no browser — Firefox is tarball)
# --------------------------------------------------
info "Installing system packages..."
apt-get update -qq
apt-get install -y -qq \
    python3 python3-pip python3-venv python3-dev \
    xserver-xorg x11-xserver-utils xinit openbox \
    unclutter curl wget git bzip2 \
    fonts-dejavu fonts-liberation fonts-noto \
    libxt6 libxmu6   # needed by Firefox on some systems

# --------------------------------------------------
# 3. Install Firefox (Mozilla tarball — no snap)
# --------------------------------------------------
FIREFOX_DIR=/opt/firefox
FIREFOX_BIN=$FIREFOX_DIR/firefox
FIREFOX_TARBALL="$INSTALL_DIR/firefox-latest.tar.bz2"

install_firefox_tarball() {
    info "Installing Firefox from Mozilla tarball..."
    mkdir -p "$FIREFOX_DIR"

    if [ -f "$FIREFOX_TARBALL" ]; then
        info "Using local tarball: $FIREFOX_TARBALL"
    else
        info "Downloading Firefox for Linux ARM64..."
        wget -q --show-progress \
            -O "$FIREFOX_TARBALL" \
            "https://ftp.mozilla.org/pub/firefox/releases/latest/linux-aarch64/en-US/firefox-latest.tar.bz2" \
            || { warn "Download failed — will need manual download"; return 1; }
    fi

    info "Extracting to $FIREFOX_DIR..."
    tar -xjf "$FIREFOX_TARBALL" -C /opt/ 2>/dev/null \
        || tar -xf "$FIREFOX_TARBALL" -C /opt/ 2>/dev/null \
        || err "Failed to extract Firefox tarball"

    if [ -f "$FIREFOX_BIN" ]; then
        ln -sf "$FIREFOX_BIN" /usr/local/bin/firefox
        info "Firefox installed at $FIREFOX_BIN"
        return 0
    fi
    return 1
}

if command -v firefox &>/dev/null; then
    info "Firefox already installed at $(which firefox)"
elif command -v firefox-esr &>/dev/null; then
    info "Firefox ESR already installed at $(which firefox-esr)"
    ln -sf "$(which firefox-esr)" /usr/local/bin/firefox
elif [ -f "$FIREFOX_BIN" ]; then
    info "Firefox tarball already present at $FIREFOX_BIN"
    ln -sf "$FIREFOX_BIN" /usr/local/bin/firefox
else
    install_firefox_tarball || {
        warn ""
        warn "==========================================="
        warn "Firefox could not be downloaded/installed."
        warn "Please download manually from:"
        warn "  https://ftp.mozilla.org/pub/firefox/releases/latest/linux-aarch64/en-US/"
        warn "Place the tarball at:"
        warn "  $FIREFOX_TARBALL"
        warn "Then re-run this installer."
        warn "==========================================="
        warn ""
    }
fi

# --------------------------------------------------
# 4. Create Firefox kiosk profile
# --------------------------------------------------
FF_PROFILE="$INSTALL_DIR/firefox-profile"
mkdir -p "$FF_PROFILE"

cat > "$FF_PROFILE/user.js" << 'FIREFOX_JS'
user_pref("dom.disable_open_during_load", true);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.privatebrowsing.autostart", true);
user_pref("browser.startup.page", 0);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("media.autoplay.default", 0);
user_pref("full-screen-api.warning.timeout", 0);
user_pref("browser.fullscreen.autohide", true);
user_pref("browser.disableResetPrompt", true);
user_pref("dom.popup_maximum", 0);
user_pref("signon.rememberSignons", false);
user_pref("browser.ctrlTab.recentlyUsedOrder", false);
user_pref("dom.allow_scripts_to_close_windows", true);
user_pref("pdfjs.disabled", true);
user_pref("browser.aboutConfig.showWarning", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("browser.tabs.allowTabDetach", false);
user_pref("browser.tabs.closeWindowWithLastTab", false);
user_pref("dom.disable_beforeunload", true);
FIREFOX_JS

chown -R "$USERNAME:$USERNAME" "$FF_PROFILE"

# --------------------------------------------------
# 5. Python virtual environment
# --------------------------------------------------
info "Creating Python virtual environment..."
python3 -m venv "$INSTALL_DIR/venv"
source "$INSTALL_DIR/venv/bin/activate"
pip install --upgrade pip wheel -q
pip install flask gunicorn requests -q

# --------------------------------------------------
# 6. Create deploy scripts (Firefox-based)
# --------------------------------------------------
info "Creating deploy scripts..."

cat > "$INSTALL_DIR/deploy/scripts/rotate-display.sh" << 'SCRIPT'
#!/bin/bash
export DISPLAY=:0
sleep 2
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
# Blocking Firefox kiosk launcher
# Runs in foreground — systemd or openbox waits on this.
# No polling, no fork bomb.
export DISPLAY=:0

# Kill stale Firefox processes (avoid multiple instances)
pkill -9 firefox 2>/dev/null || true
sleep 2

while true; do
    firefox \
        --kiosk \
        --no-remote \
        --new-instance \
        --profile /opt/leidsa-dashboard/firefox-profile \
        http://localhost:5000
    sleep 5
done
SCRIPT

cat > "$INSTALL_DIR/deploy/scripts/autostart.sh" << 'SCRIPT'
#!/bin/bash
# Direct kiosk launcher for use with systemd kiosk.service
# This runs in foreground so systemd can track and restart it
export DISPLAY=:0

# Ensure X is ready
sleep 3

# Kill stale Firefox processes
pkill -9 firefox 2>/dev/null || true
sleep 1

exec firefox \
    --kiosk \
    --no-remote \
    --new-instance \
    --profile /opt/leidsa-dashboard/firefox-profile \
    http://localhost:5000
SCRIPT

cat > "$INSTALL_DIR/deploy/scripts/openbox-autostart.sh" << 'SCRIPT'
#!/bin/bash
# This file goes in ~/.config/openbox/autostart
/opt/leidsa-dashboard/deploy/scripts/disable-blanking.sh &
/opt/leidsa-dashboard/deploy/scripts/rotate-display.sh &
unclutter -idle 0.5 &
sleep 5
exec /opt/leidsa-dashboard/deploy/scripts/watchdog.sh
SCRIPT

cat > "$INSTALL_DIR/deploy/scripts/healthcheck.sh" << 'SCRIPT'
#!/bin/bash
URL=http://localhost:5000/health
STATUS=$(curl -s $URL)
if [[ $STATUS != *ok* ]]; then
    systemctl restart leidsa.service
fi
SCRIPT

cat > "$INSTALL_DIR/deploy/scripts/set-fallback-ip.sh" << 'SCRIPT'
#!/bin/bash
FALLBACK_IP=192.168.1.250/24
IFACE=eth0
if ! ip addr show "$IFACE" | grep -q "$FALLBACK_IP"; then
    ip addr add "$FALLBACK_IP" dev "$IFACE"
fi
SCRIPT

chmod +x "$INSTALL_DIR/deploy/scripts/"*.sh

# --------------------------------------------------
# 7. Systemd services
# --------------------------------------------------
info "Installing systemd services..."

# leidsa.service (Flask backend)
cp "$INSTALL_DIR/deploy/systemd/leidsa.service" /etc/systemd/system/
sed -i "s/__USER__/$USERNAME/g" /etc/systemd/system/leidsa.service

# fallback-ip.service
cp "$INSTALL_DIR/deploy/systemd/fallback-ip.service" /etc/systemd/system/

systemctl daemon-reload
systemctl enable leidsa.service
systemctl enable fallback-ip.service

# Note: kiosk.service not used — Firefox is launched via openbox autostart
# (watchdog.sh runs in a blocking loop, systemd isn't needed)

# --------------------------------------------------
# 8. Autologin
# --------------------------------------------------
info "Configuring autologin..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << UNIT
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear %I \$TERM
UNIT

# --------------------------------------------------
# 9. Openbox + X startup
# --------------------------------------------------
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

cp "$INSTALL_DIR/deploy/scripts/openbox-autostart.sh" \
   "$USER_HOME/.config/openbox/autostart"
chmod +x "$USER_HOME/.config/openbox/autostart"

chown -R "$USERNAME:$USERNAME" \
    "$USER_HOME/.bash_profile" \
    "$USER_HOME/.xinitrc" \
    "$USER_HOME/.config"

# --------------------------------------------------
# 10. Kernel panic reboot
# --------------------------------------------------
info "Setting kernel panic reboot..."
cat >> /etc/sysctl.conf << SYSCTL
kernel.panic=10
kernel.panic_on_oops=1
SYSCTL
sysctl -p

# --------------------------------------------------
# 11. Logrotate
# --------------------------------------------------
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

# --------------------------------------------------
# 12. Cron jobs
# --------------------------------------------------
info "Creating cron jobs..."
(crontab -u "$USERNAME" -l 2>/dev/null; echo "0 4 * * * /sbin/reboot") | crontab -u "$USERNAME" -
(crontab -u "$USERNAME" -l 2>/dev/null; echo "*/5 * * * * $INSTALL_DIR/deploy/scripts/healthcheck.sh") | crontab -u "$USERNAME" -

# --------------------------------------------------
# 13. Helper symlinks
# --------------------------------------------------
info "Creating helper symlinks..."
mkdir -p /usr/local/bin
ln -sf "$INSTALL_DIR/deploy/dashboard-status" /usr/local/bin/dashboard-status 2>/dev/null || true
ln -sf "$INSTALL_DIR/deploy/update.sh" /usr/local/bin/update-dashboard 2>/dev/null || true
ln -sf "$INSTALL_DIR/deploy/backup.sh" /usr/local/bin/backup-dashboard 2>/dev/null || true

mkdir -p "$INSTALL_DIR/logs"
chown -R "$USERNAME:$USERNAME" "$INSTALL_DIR"

# --------------------------------------------------
# 14. Start services
# --------------------------------------------------
info "Starting services..."
systemctl start leidsa.service
systemctl start fallback-ip.service

info ""
info "=== INSTALLATION COMPLETE ==="
info ""
info "  Backend:  http://localhost:5000 (Flask + Gunicorn)"
info "  Kiosk:    openbox autostart → watchdog.sh → Firefox"
info "  Fallback: 192.168.1.250/24 on eth0"
info ""
echo -e "  ${YELLOW}Reboot now?${NC} [y/N] \c"
read -r REBOOT
if [ "$REBOOT" = "y" ] || [ "$REBOOT" = "Y" ]; then
    info "Rebooting..."
    reboot
fi
