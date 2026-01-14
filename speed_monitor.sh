#!/bin/bash
# Internet Speed Monitor Script
# Logs speed test results to CSV every time it's run

# Configuration - unified with SwiftBar/nkspeedtest
DATA_DIR="$HOME/.local/share/nkspeedtest"
CSV_FILE="$DATA_DIR/speed_log.csv"
LOG_FILE="$DATA_DIR/speed_monitor.log"

# Ensure data directory exists
mkdir -p "$DATA_DIR"

# User info for CSV
USER_NAME="${USER:-$(whoami)}"
HOSTNAME_NAME="${HOSTNAME:-$(hostname -s)}"

# Create CSV header if file doesn't exist (format matches SwiftBar plugin)
if [ ! -f "$CSV_FILE" ]; then
    echo "timestamp,date,time,user,hostname,download_mbps,upload_mbps,ping_ms,network_ssid,external_ip,status" > "$CSV_FILE"
fi

# Get current timestamp
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
DATE_ONLY=$(date +"%Y-%m-%d")
TIME_ONLY=$(date +"%H:%M:%S")

# Get connected WiFi network name
NETWORK_SSID=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | awk -F': ' '/^ *SSID/ {print $2}')
if [ -z "$NETWORK_SSID" ]; then
    NETWORK_SSID="Unknown/Ethernet"
fi

# Log start
echo "[$TIMESTAMP] Starting speed test..." >> "$LOG_FILE"

# Run speed test and capture output
SPEEDTEST_OUTPUT=$(speedtest-cli --simple 2>&1)
SPEEDTEST_EXIT=$?

if [ $SPEEDTEST_EXIT -eq 0 ]; then
    # Parse results
    PING=$(echo "$SPEEDTEST_OUTPUT" | grep "Ping:" | awk '{print $2}')
    DOWNLOAD=$(echo "$SPEEDTEST_OUTPUT" | grep "Download:" | awk '{print $2}')
    UPLOAD=$(echo "$SPEEDTEST_OUTPUT" | grep "Upload:" | awk '{print $2}')
    STATUS="success"

    # Get external IP
    EXTERNAL_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "N/A")

    echo "[$TIMESTAMP] Test completed - Down: ${DOWNLOAD} Mbps, Up: ${UPLOAD} Mbps, Ping: ${PING} ms" >> "$LOG_FILE"
else
    PING="0"
    DOWNLOAD="0"
    UPLOAD="0"
    EXTERNAL_IP="N/A"
    STATUS="failed"
    echo "[$TIMESTAMP] Speed test failed: $SPEEDTEST_OUTPUT" >> "$LOG_FILE"
fi

# Append to CSV (format: timestamp,date,time,user,hostname,download,upload,ping,ssid,ip,status)
echo "$TIMESTAMP,$DATE_ONLY,$TIME_ONLY,$USER_NAME,$HOSTNAME_NAME,$DOWNLOAD,$UPLOAD,$PING,$NETWORK_SSID,$EXTERNAL_IP,$STATUS" >> "$CSV_FILE"

# Print summary to stdout
echo "=== Speed Test Results ==="
echo "Time: $TIMESTAMP"
echo "Network: $NETWORK_SSID"
echo "Download: $DOWNLOAD Mbps"
echo "Upload: $UPLOAD Mbps"
echo "Ping: $PING ms"
echo "Status: $STATUS"
echo "Results saved to: $CSV_FILE"
