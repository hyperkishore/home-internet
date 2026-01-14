#!/bin/bash

# SwiftBar plugin for speed-monitor
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>

# Config paths
CONFIG_DIR="$HOME/.config/speed-monitor"
DATA_DIR="$HOME/.local/share/speed-monitor"
CSV_FILE="$DATA_DIR/speed_log.csv"
CONFIG_FILE="$CONFIG_DIR/config"

# Load config
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Get the latest entry from CSV (skip header)
if [[ -f "$CSV_FILE" ]]; then
    LATEST=$(tail -1 "$CSV_FILE")

    # Parse CSV fields
    # timestamp,date,time,user,hostname,download_mbps,upload_mbps,ping_ms,network_ssid,external_ip,status
    IFS=',' read -r timestamp date time user hostname download upload ping ssid ip status <<< "$LATEST"

    # Trim whitespace
    download=$(echo "$download" | xargs)
    upload=$(echo "$upload" | xargs)
    ping=$(echo "$ping" | xargs)
    status=$(echo "$status" | xargs)
    time=$(echo "$time" | xargs)

    # Check if we have valid data
    if [[ "$status" == "success" && -n "$download" ]]; then
        # Menu bar display (compact)
        echo "↓${download} ↑${upload} | sfimage=wifi"
    else
        echo "⚠ Offline | sfimage=wifi.slash"
    fi

    echo "---"
    echo "Internet Speed Monitor | size=14"
    echo "---"
    echo "Download: ${download} Mbps | sfimage=arrow.down.circle"
    echo "Upload: ${upload} Mbps | sfimage=arrow.up.circle"
    echo "Ping: ${ping} ms | sfimage=clock"
    echo "---"
    echo "User: ${USER_NAME:-$user} | sfimage=person"
    echo "Last Test: ${time} | sfimage=calendar"
    echo "---"
    echo "Open Dashboard | bash='speed-monitor' param1=dashboard terminal=false sfimage=chart.line.uptrend.xyaxis"
    echo "Run Speed Test Now | bash='speed-monitor' param1=run terminal=false refresh=true sfimage=play.circle"
    echo "---"
    echo "View Logs | bash='speed-monitor' param1=logs terminal=true sfimage=doc.text"
else
    echo "⚠ No Data | sfimage=wifi.slash"
    echo "---"
    echo "CSV file not found"
    echo "Run 'speed-monitor setup' first"
fi
