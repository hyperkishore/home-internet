#!/bin/bash

# NK Speed Test - SwiftBar Plugin
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>

CSV_FILE="$HOME/.local/share/nkspeedtest/speed_log.csv"
SPEED_MONITOR="$HOME/.local/bin/speed_monitor.sh"
DASHBOARD_URL="http://localhost:8080/dashboard.html"

# Get the latest entry from CSV
if [[ -f "$CSV_FILE" ]]; then
    LATEST=$(tail -1 "$CSV_FILE")

    # Parse CSV: timestamp,date,time,user,hostname,download_mbps,upload_mbps,ping_ms,network_ssid,external_ip,status
    IFS=',' read -r timestamp date time user hostname download upload ping ssid ip status <<< "$LATEST"

    # Trim whitespace
    download=$(echo "$download" | xargs)
    upload=$(echo "$upload" | xargs)
    ping=$(echo "$ping" | xargs)
    status=$(echo "$status" | xargs)
    time=$(echo "$time" | xargs)
    date=$(echo "$date" | xargs)
    ssid=$(echo "$ssid" | xargs)

    # Check if we have valid data
    if [[ "$status" == "success" && -n "$download" ]]; then
        echo "↓$download ↑$upload | sfimage=wifi"
    else
        echo "⚠ Offline | sfimage=wifi.slash"
    fi

    echo "---"
    echo "Internet Speed Monitor | size=14"
    echo "---"
    echo "Download: $download Mbps | sfimage=arrow.down.circle"
    echo "Upload: $upload Mbps | sfimage=arrow.up.circle"
    echo "Ping: $ping ms | sfimage=clock"
    echo "---"
    echo "Network: $ssid | sfimage=wifi"
    echo "Last Test: $date $time | sfimage=calendar"
    echo "---"
    echo "Run Speed Test Now | bash=$SPEED_MONITOR terminal=false refresh=true sfimage=play.circle"
    echo "Open Dashboard | bash=/usr/bin/open param1=$DASHBOARD_URL terminal=false sfimage=chart.line.uptrend.xyaxis"
    echo "---"
    echo "View Logs | bash=/usr/bin/tail param1=-20 param2=$CSV_FILE terminal=true sfimage=doc.text"
else
    echo "⚠ No Data | sfimage=wifi.slash"
    echo "---"
    echo "No speed test data yet"
    echo "---"
    echo "Run Speed Test Now | bash=$SPEED_MONITOR terminal=false refresh=true sfimage=play.circle"
fi
