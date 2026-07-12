#!/usr/bin/env python3
"""
LEIDSA Lottery Results Dashboard - Backend
Fetches data from leidsa.com/api/draw-games/game-calendars
"""
from flask import Flask, jsonify, send_from_directory
import urllib.request
import json
import threading
import time
import os
from datetime import datetime, timezone, timedelta

app = Flask(__name__, static_folder="static", static_url_path="/static")

CACHE = {"data": None, "last_updated": None, "error": None}

# Dominican Republic timezone (UTC-4)
DR_TZ = timezone(timedelta(hours=-4))

GAME_DISPLAY_NAMES = {
    ("Loto", "Leidsa"): {"display": "Loto Más", "subtitle": "Superloto", "color": "#f5a623"},
    ("KinoTV", "Leidsa"): {"display": "Super Kino", "subtitle": "TV", "color": "#e74c3c"},
    ("Loto Pool", "Leidsa"): {"display": "Loto Pool", "subtitle": "", "color": "#f5a623"},
    ("Quiniela Pale", "Leidsa"): {"display": "Palé", "subtitle": "LEIDSA", "color": "#f5a623"},
    ("Pega3Mas", "Leidsa"): {"display": "Pega3Más", "subtitle": "LEIDSA", "color": "#f5a623"},
    ("Super Pale", "Leidsa"): {"display": "Super Palé", "subtitle": "LEIDSA", "color": "#f5a623"},
    ("Quiniela Pale", "Loteria Nacional"): {"display": "Lotería", "subtitle": "Nacional", "color": "#27ae60"},
    ("Quiniela Pale", "Loteria Real"): {"display": "Anguilla", "subtitle": "Real", "color": "#2980b9"},
    ("Quiniela Pale", "Loteka"): {"display": "Quiniela", "subtitle": "Loteka", "color": "#8e44ad"},
    ("Quiniela Pale", "La Suerte"): {"display": "La Suerte", "subtitle": "", "color": "#16a085"},
    ("Quiniela Pale", "Lotedom"): {"display": "Daniel", "subtitle": "", "color": "#d35400"},
    ("Quiniela Pale", "La Primera"): {"display": "La Primera", "subtitle": "", "color": "#c0392b"},
    ("Super Pale", "La Primera"): {"display": "Super Palé", "subtitle": "La Primera", "color": "#c0392b"},
    ("Super Pale", "La Suerte"): {"display": "Super Palé", "subtitle": "La Suerte", "color": "#16a085"},
    ("Super Pale", "Loteka"): {"display": "Super Palé", "subtitle": "Loteka", "color": "#8e44ad"},
    ("Super Pale", "Loteria Real"): {"display": "Super Palé", "subtitle": "Anguilla Real", "color": "#2980b9"},
    ("Super Pale", "Lotedom"): {"display": "Super Palé", "subtitle": "Daniel", "color": "#d35400"},
}

def format_timestamp(ts):
    """Convert UTC timestamp to DR local time string."""
    if not ts:
        return ""
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        local = dt.astimezone(DR_TZ)
        days = {0: "Lun", 1: "Mar", 2: "Mié", 3: "Jue", 4: "Vie", 5: "Sáb", 6: "Dom"}
        months = {1: "Ene", 2: "Feb", 3: "Mar", 4: "Abr", 5: "May", 6: "Jun",
                  7: "Jul", 8: "Ago", 9: "Sep", 10: "Oct", 11: "Nov", 12: "Dic"}
        return f"{days[local.weekday()]}, {months[local.month]} {local.day:02d}, {local.strftime('%H:%M')}"
    except Exception:
        return ts[:10]

def fetch_leidsa_data():
    """Fetch lottery results from leidsa.com API."""
    headers = {
        "User-Agent": "Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36",
        "Accept": "application/json, */*",
        "Accept-Language": "es-DO,es;q=0.9,en;q=0.8",
        "Referer": "https://www.leidsa.com/",
        "Cache-Control": "no-cache"
    }
    url = "https://www.leidsa.com/api/draw-games/game-calendars"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as r:
        raw = json.loads(r.read().decode("utf-8"))

    games = []
    seen_keys = set()

    for game in raw.get("gamesCalendar", []):
        gid = game.get("gameId", {})
        family = gid.get("gameFamilyName", "")
        provider = gid.get("gameProvider", "")
        key = (family, provider)

        # Skip duplicates (Super Pale entries per provider)
        if key in seen_keys:
            continue
        seen_keys.add(key)

        prev = game.get("previousDrawDetails") or {}
        next_draw = game.get("nextDrawDetails") or {}

        display_info = GAME_DISPLAY_NAMES.get(key, {
            "display": family,
            "subtitle": provider,
            "color": "#3498db"
        })

        min_display = game.get("minNumberDisplay", 1)
        numbers = prev.get("drawnValues", [])
        bonus = prev.get("bonusRoundsValues", [])

        # Format numbers with leading zeros if needed
        fmt = lambda n: f"{n:02d}" if min_display > 1 else str(n)

        games.append({
            "family": family,
            "provider": provider,
            "display": display_info["display"],
            "subtitle": display_info["subtitle"],
            "color": display_info["color"],
            "numbers": [fmt(n) for n in numbers],
            "bonus": [fmt(n) for n in bonus],
            "drawDate": format_timestamp(prev.get("drawTimestamp", "")),
            "drawTimestamp": prev.get("drawTimestamp", ""),
            "nextDraw": format_timestamp(next_draw.get("drawTimestamp", "")),
            "drawId": prev.get("drawId", ""),
            "slug": game.get("slug", ""),
            "minDisplay": min_display,
            "isFavourite": game.get("isFavourite", False),
        })

    return games

def refresh_loop():
    """Background thread to refresh lottery data every 2 minutes."""
    while True:
        try:
            data = fetch_leidsa_data()
            CACHE["data"] = data
            CACHE["last_updated"] = datetime.now(DR_TZ).strftime("%d/%m/%Y %H:%M:%S")
            CACHE["error"] = None
            print(f"[{CACHE['last_updated']}] Data refreshed: {len(data)} games loaded")
        except Exception as e:
            CACHE["error"] = str(e)
            print(f"Error fetching data: {e}")
        time.sleep(120)  # Refresh every 2 minutes

@app.route("/api/results")
def results():
    if CACHE["data"] is None and CACHE["error"] is None:
        try:
            data = fetch_leidsa_data()
            CACHE["data"] = data
            CACHE["last_updated"] = datetime.now(DR_TZ).strftime("%d/%m/%Y %H:%M:%S")
        except Exception as e:
            CACHE["error"] = str(e)
            return jsonify({"error": str(e)}), 500
    return jsonify({
        "games": CACHE["data"] or [],
        "lastUpdated": CACHE["last_updated"],
        "error": CACHE["error"]
    })

@app.route("/")
def index():
    return send_from_directory("static", "index.html")

@app.route("/health")
def health():
    return jsonify({"status": "ok", "lastUpdated": CACHE["last_updated"]})

# Initial fetch at module level (runs on import, including under Gunicorn)
try:
    data = fetch_leidsa_data()
    CACHE["data"] = data
    CACHE["last_updated"] = datetime.now(DR_TZ).strftime("%d/%m/%Y %H:%M:%S")
    print(f"Initial data loaded: {len(data)} games")
except Exception as e:
    print(f"Initial fetch error: {e}")

# Start background refresh thread (daemon so it doesn't block shutdown)
t = threading.Thread(target=refresh_loop, daemon=True)
t.start()

if __name__ == "__main__":
    print("Starting LEIDSA Dashboard Backend...")
    app.run(host="0.0.0.0", port=5000, debug=False, use_reloader=False)
