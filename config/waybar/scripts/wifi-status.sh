#!/usr/bin/env bash

# Quick status string for polybar.

# Check if Wi-Fi is enabled
radio=$(nmcli -t -f WIFI g)
if [[ "$radio" != "enabled" ]]; then
    echo "󰖪 OFF"
    exit
fi

# Get current active Wi-Fi connection info
active_ssid=$(nmcli -t -f active,ssid dev wifi | awk -F: '$1=="yes"{print $2}')
if [[ -z "$active_ssid" ]]; then
    echo "󰖪 Disconnected"
    exit
fi

# Signal strength
signal=$(nmcli -t -f active,signal dev wifi | awk -F: '$1=="yes"{print $2}')
# Device name (the connected wifi device)
device=$(nmcli -t -f DEVICE,TYPE,STATE dev status | awk -F: '$2=="wifi" && $3=="connected"{print $1}')
# IP address
ip=$(nmcli -t -f IP4.ADDRESS dev show "$device" | head -n1 | cut -d: -f2 | sed 's/\/.*//;s/^[ \t]*//')

# Choose icon based on signal
icon="󰖩"
if [[ "$signal" -lt 30 ]]; then
    icon="󰤢"  # weak
elif [[ "$signal" -lt 60 ]]; then
    icon="󰤥"  # medium
elif [[ "$signal" -lt 85 ]]; then
    icon="󰤨"  # good
else
    icon="󰤭"  # excellent
fi

echo "$icon $active_ssid ${signal}% $ip"
