#!/bin/bash
FALLBACK_IP=192.168.1.250/24
IFACE=eth0
if ! ip addr show "$IFACE" | grep -q "$FALLBACK_IP"; then
    ip addr add "$FALLBACK_IP" dev "$IFACE"
fi
