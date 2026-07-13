#!/bin/bash
# Configure eth0 for DHCP + fallback IP via NetworkManager
# This replaces the old systemd fallback-ip.service approach

FALLBACK_IP=192.168.1.250/24
IFACE=eth0
CONN_NAME=$IFACE

# Create/update NM connection with DHCP + static fallback address
if nmcli -t connection show "$CONN_NAME" &>/dev/null; then
    nmcli connection modify "$CONN_NAME" \
        ipv4.method auto \
        ipv4.addresses "$FALLBACK_IP" \
        connection.autoconnect yes
else
    nmcli connection add type ethernet \
        con-name "$CONN_NAME" \
        ifname "$IFACE" \
        ipv4.method auto \
        ipv4.addresses "$FALLBACK_IP" \
        connection.autoconnect yes
fi

# Reapply the connection to get both IPs
nmcli connection down "$CONN_NAME" 2>/dev/null
nmcli connection up "$CONN_NAME"
