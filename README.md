# PiKiosk — LEIDSA Lottery Dashboard Kiosk

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A full-screen kiosk dashboard for displaying LEIDSA lottery results with rotating ads, built for single-board computers (Orange Pi, Raspberry Pi, etc.).

## Features

- **Live lottery results** — Displays LEIDSA and other Dominican lottery results with animated number balls
- **Ad rotation** — 4 rotating ad slots (30s each, 2min cycle), easily extensible
- **Auto-refresh** — Data refreshes every 2 minutes
- **Dual-slide layout** — Toggles between LEIDSA results and other lotteries every 60s
- **Kiosk browser** — Firefox in fullscreen kiosk mode with pre-initialized profile (no dialogs)
- **Responsive sizing** — Cards and balls auto-fit to screen resolution
- **Fallback IP** — DHCP + static secondary IP via NetworkManager

## Hardware

- **Recommended:** Orange Pi Zero 2W (2 GB RAM)
- **OS:** Ubuntu 22.04 (ARM64) or any Debian-based Linux
- **Display:** HDMI monitor in portrait orientation (rotated via xrandr)

## Quick Install

```bash
# Clone repo on the target device
git clone https://github.com/javive17/pikiosk.git /opt/leidsa-dashboard

# Run installer
bash /opt/leidsa-dashboard/install.sh
```

The installer will:
1. Install system dependencies (Xorg, Openbox, Firefox, Python, etc.)
2. Download and extract Firefox ARM64 tarball to `/opt/firefox`
3. Create Python virtual environment with Flask + Gunicorn
4. Create Firefox kiosk profile with optimized preferences
5. Install `leidsa.service` (Flask backend on port 5000)
6. Configure NetworkManager for DHCP + fallback static IP (`192.168.1.250`)
7. Set up auto-login + startx + Openbox autostart
8. Install logrotate, healthcheck cron, watchdog, and reboot timers

## Manual Setup (if install.sh is not used)

1. Deploy files to `/opt/leidsa-dashboard/`
2. Install Python deps: `pip install flask gunicorn requests`
3. Install Firefox ARM64 tarball to `/opt/firefox/`, symlink to `/usr/local/bin/firefox`
4. Copy `deploy/systemd/leidsa.service` to `/etc/systemd/system/` and enable
5. Copy `deploy/scripts/openbox-autostart.sh` to `~/.config/openbox/autostart`
6. Configure auto-login + startx in `~/.bash_profile`
7. Run `deploy/scripts/set-fallback-ip.sh` to configure NM secondary IP

## Project Structure

```
/opt/leidsa-dashboard/
├── app.py                          # Flask backend
├── static/
│   ├── index.html                  # Kiosk dashboard UI
│   ├── quisqueya-bottle.png        # Ad asset
│   └── quisqueya-bottle.jpg        # Ad asset fallback
├── firefox-profile/
│   └── user.js                     # Firefox kiosk preferences
├── venv/                           # Python virtual environment
└── deploy/
    ├── scripts/
    │   ├── watchdog.sh             # Blocking Firefox kiosk launcher
    │   ├── openbox-autostart.sh    # Openbox autostart entry point
    │   ├── set-fallback-ip.sh      # NM fallback IP configuration
    │   ├── disable-blanking.sh     # Screen blanking/power management
    │   ├── rotate-display.sh       # Portrait rotation via xrandr
    │   ├── autostart.sh            # Direct Firefox launcher (legacy)
    │   ├── backup.sh               # Database backup
    │   ├── healthcheck.sh          # Cron healthcheck script
    │   └── update.sh               # Git pull & restart
    └── systemd/
        └── leidsa.service          # Flask backend systemd unit
```

## Adding Ads

Edit `static/index.html`:

1. **Add CSS** — Create a variant class (e.g., `.ad-promo--mybrand`) with custom colors/gradients
2. **Add HTML** — Insert a new `.ad-slide` div inside `#adZone` following the existing pattern
3. **Adjust timer** — Change `AD_ROTATE_INTERVAL` (currently 30000ms for 4 ads @ 2min cycle)

The rotating script uses `document.querySelectorAll('.ad-slide')` so new slides are picked up automatically.

## API Endpoint

| URL | Description |
|-----|-------------|
| `http://localhost:5000` | Kiosk dashboard |
| `http://localhost:5000/api/results` | JSON lottery results |
| `http://localhost:5000/health` | Health check |

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Black screen on boot | Wait for profile pre-initialization; or kill Firefox (watchdog restarts it) |
| "No info" on dashboard | leidsa.com API is behind Cloudflare — Python backend can't bypass the JS challenge |
| No fallback IP | Run `bash /opt/leidsa-dashboard/deploy/scripts/set-fallback-ip.sh` |
| Firefox not starting | Check `~/.config/openbox/autostart` has `exec /opt/leidsa-dashboard/deploy/scripts/watchdog.sh` |
| Portrait rotation | Edit `rotate-display.sh` or remove if display is landscape |

## Credits

Built by [@javive17](https://github.com/javive17). Powered by Flask, Firefox, and Orange Pi.
