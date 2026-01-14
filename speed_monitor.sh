#!/bin/bash
#
# Speed Monitor v2.0.0 - Organization-Wide Internet Speed Monitoring
# Enhanced data collection for fleet deployment (300+ devices)
#

VERSION="2.0.0"

# Configuration
DATA_DIR="$HOME/.local/share/nkspeedtest"
CONFIG_DIR="$HOME/.config/nkspeedtest"
CSV_FILE="$DATA_DIR/speed_log.csv"
LOG_FILE="$DATA_DIR/speed_monitor.log"
WIFI_HELPER="$HOME/.local/bin/wifi_info"

# Server configuration (optional)
SERVER_URL="${SPEED_MONITOR_SERVER:-}"

# Ensure directories exist
mkdir -p "$DATA_DIR" "$CONFIG_DIR"

# CSV Header (v2.0 schema)
CSV_HEADER="timestamp_utc,device_id,os_version,app_version,timezone,interface,ssid,bssid,band,channel,width_mhz,rssi_dbm,noise_dbm,snr_db,tx_rate_mbps,local_ip,public_ip,latency_ms,jitter_ms,jitter_p50,jitter_p95,packet_loss_pct,download_mbps,upload_mbps,vpn_status,vpn_name,errors,raw_payload"

# Create CSV header if file doesn't exist
if [[ ! -f "$CSV_FILE" ]]; then
    echo "$CSV_HEADER" > "$CSV_FILE"
fi

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Get stable device ID (persisted across reinstalls)
get_device_id() {
    local device_id_file="$CONFIG_DIR/device_id"
    if [[ -f "$device_id_file" ]]; then
        cat "$device_id_file"
    else
        # Generate from hardware UUID for stability
        local hw_uuid=$(ioreg -rd1 -c IOPlatformExpertDevice | awk '/IOPlatformUUID/ { print $3 }' | tr -d '"')
        echo "$hw_uuid" | shasum -a 256 | cut -c1-16 > "$device_id_file"
        cat "$device_id_file"
    fi
}

# Get WiFi details via CoreWLAN Swift helper
get_wifi_details() {
    if [[ -x "$WIFI_HELPER" ]]; then
        "$WIFI_HELPER"
    else
        # Fallback: try legacy airport command
        local airport="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
        if [[ -x "$airport" ]]; then
            local ssid=$("$airport" -I 2>/dev/null | awk -F': ' '/^ *SSID/ {print $2}')
            local bssid=$("$airport" -I 2>/dev/null | awk -F': ' '/^ *BSSID/ {print $2}')
            local channel=$("$airport" -I 2>/dev/null | awk -F': ' '/^ *channel/ {print $2}' | cut -d',' -f1)
            local rssi=$("$airport" -I 2>/dev/null | awk -F': ' '/^ *agrCtlRSSI/ {print $2}')
            local noise=$("$airport" -I 2>/dev/null | awk -F': ' '/^ *agrCtlNoise/ {print $2}')

            echo "CONNECTED=true"
            echo "INTERFACE=en0"
            echo "SSID=${ssid:-Unknown}"
            echo "BSSID=${bssid:-unknown}"
            echo "CHANNEL=${channel:-0}"
            echo "BAND=unknown"
            echo "WIDTH_MHZ=0"
            echo "RSSI_DBM=${rssi:-0}"
            echo "NOISE_DBM=${noise:-0}"
            echo "SNR_DB=0"
            echo "TX_RATE_MBPS=0"
        else
            echo "CONNECTED=false"
            echo "INTERFACE=none"
            echo "SSID=Unknown/Ethernet"
            echo "BSSID=unknown"
            echo "CHANNEL=0"
            echo "BAND=unknown"
            echo "WIDTH_MHZ=0"
            echo "RSSI_DBM=0"
            echo "NOISE_DBM=0"
            echo "SNR_DB=0"
            echo "TX_RATE_MBPS=0"
        fi
    fi
}

# Detect VPN status
detect_vpn() {
    local vpn_status="disconnected"
    local vpn_name="none"

    # Zscaler Client Connector
    if pgrep -x "Zscaler" > /dev/null 2>&1 || pgrep -x "ZscalerTunnel" > /dev/null 2>&1; then
        vpn_status="connected"
        vpn_name="Zscaler"
    # Cisco AnyConnect
    elif pgrep -x "vpnagentd" > /dev/null 2>&1; then
        vpn_status="connected"
        vpn_name="Cisco AnyConnect"
    # Palo Alto GlobalProtect
    elif pgrep -x "PanGPS" > /dev/null 2>&1 || pgrep -x "GlobalProtect" > /dev/null 2>&1; then
        vpn_status="connected"
        vpn_name="GlobalProtect"
    # Fortinet FortiClient
    elif pgrep -x "FortiClient" > /dev/null 2>&1; then
        vpn_status="connected"
        vpn_name="FortiClient"
    # OpenVPN
    elif pgrep -x "openvpn" > /dev/null 2>&1; then
        vpn_status="connected"
        vpn_name="OpenVPN"
    # Tunnelblick (OpenVPN GUI)
    elif pgrep -x "Tunnelblick" > /dev/null 2>&1; then
        vpn_status="connected"
        vpn_name="Tunnelblick"
    # WireGuard
    elif pgrep -x "wireguard-go" > /dev/null 2>&1; then
        vpn_status="connected"
        vpn_name="WireGuard"
    # Generic: check for utun interfaces (VPN tunnels)
    elif ifconfig 2>/dev/null | grep -q "^utun"; then
        # Check if any utun interface has an IP
        if ifconfig 2>/dev/null | grep -A1 "^utun" | grep -q "inet "; then
            vpn_status="connected"
            vpn_name="Unknown VPN"
        fi
    fi

    echo "VPN_STATUS=$vpn_status"
    echo "VPN_NAME=$vpn_name"
}

# Run ping test for jitter and packet loss calculation
run_ping_test() {
    local target="${1:-8.8.8.8}"
    local count="${2:-15}"

    # Run ping and capture output
    local ping_output=$(ping -c "$count" -q "$target" 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo "JITTER_MS=0"
        echo "JITTER_P50=0"
        echo "JITTER_P95=0"
        echo "PACKET_LOSS_PCT=100"
        return
    fi

    # Extract packet loss
    local packet_loss=$(echo "$ping_output" | grep "packet loss" | sed 's/.*\([0-9.]*\)% packet loss.*/\1/')
    packet_loss=${packet_loss:-0}

    # Run detailed ping for jitter calculation
    local detailed_ping=$(ping -c "$count" "$target" 2>&1)

    # Extract RTT values
    local rtt_values=$(echo "$detailed_ping" | grep "time=" | sed 's/.*time=\([0-9.]*\).*/\1/')

    # Calculate jitter using awk
    local jitter_stats=$(echo "$rtt_values" | awk '
    BEGIN { n=0; prev=0; sum_diff=0 }
    NF > 0 {
        values[n] = $1
        if (n > 0) {
            diff = ($1 > prev) ? ($1 - prev) : (prev - $1)
            sum_diff += diff
        }
        prev = $1
        n++
    }
    END {
        if (n <= 1) {
            print "0 0 0"
            exit
        }

        # Mean jitter
        jitter = sum_diff / (n - 1)

        # Sort for percentiles
        for (i = 0; i < n; i++) {
            for (j = i + 1; j < n; j++) {
                if (values[i] > values[j]) {
                    tmp = values[i]
                    values[i] = values[j]
                    values[j] = tmp
                }
            }
        }

        # P50 (median)
        p50_idx = int(n * 0.5)
        p50 = values[p50_idx]

        # P95
        p95_idx = int(n * 0.95)
        if (p95_idx >= n) p95_idx = n - 1
        p95 = values[p95_idx]

        printf "%.2f %.2f %.2f\n", jitter, p50, p95
    }')

    local jitter=$(echo "$jitter_stats" | awk '{print $1}')
    local p50=$(echo "$jitter_stats" | awk '{print $2}')
    local p95=$(echo "$jitter_stats" | awk '{print $3}')

    echo "JITTER_MS=${jitter:-0}"
    echo "JITTER_P50=${p50:-0}"
    echo "JITTER_P95=${p95:-0}"
    echo "PACKET_LOSS_PCT=${packet_loss:-0}"
}

# Get local IP address
get_local_ip() {
    # Get IP of the primary interface
    local ip=$(ipconfig getifaddr en0 2>/dev/null)
    if [[ -z "$ip" ]]; then
        ip=$(ipconfig getifaddr en1 2>/dev/null)
    fi
    if [[ -z "$ip" ]]; then
        ip=$(ifconfig 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}')
    fi
    echo "${ip:-unknown}"
}

# Build JSON payload
build_json_payload() {
    local json="{"
    json+="\"timestamp_utc\":\"$TIMESTAMP_UTC\","
    json+="\"device_id\":\"$DEVICE_ID\","
    json+="\"os_version\":\"$OS_VERSION\","
    json+="\"app_version\":\"$VERSION\","
    json+="\"timezone\":\"$TIMEZONE\","
    json+="\"interface\":\"$INTERFACE\","
    json+="\"ssid\":\"$SSID\","
    json+="\"bssid\":\"$BSSID\","
    json+="\"band\":\"$BAND\","
    json+="\"channel\":$CHANNEL,"
    json+="\"width_mhz\":$WIDTH_MHZ,"
    json+="\"rssi_dbm\":$RSSI_DBM,"
    json+="\"noise_dbm\":$NOISE_DBM,"
    json+="\"snr_db\":$SNR_DB,"
    json+="\"tx_rate_mbps\":$TX_RATE_MBPS,"
    json+="\"local_ip\":\"$LOCAL_IP\","
    json+="\"public_ip\":\"$PUBLIC_IP\","
    json+="\"latency_ms\":$LATENCY_MS,"
    json+="\"jitter_ms\":$JITTER_MS,"
    json+="\"jitter_p50\":$JITTER_P50,"
    json+="\"jitter_p95\":$JITTER_P95,"
    json+="\"packet_loss_pct\":$PACKET_LOSS_PCT,"
    json+="\"download_mbps\":$DOWNLOAD_MBPS,"
    json+="\"upload_mbps\":$UPLOAD_MBPS,"
    json+="\"vpn_status\":\"$VPN_STATUS\","
    json+="\"vpn_name\":\"$VPN_NAME\","
    json+="\"errors\":\"$ERRORS\""
    json+="}"
    echo "$json"
}

# Main collection function
collect_metrics() {
    local errors=""

    log "Starting speed test (v$VERSION)..."

    # Timestamp and device info
    TIMESTAMP_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    DEVICE_ID=$(get_device_id)
    OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    TIMEZONE=$(date +"%z")

    # WiFi details
    log "Collecting WiFi details..."
    eval $(get_wifi_details)

    # Handle missing WiFi (Ethernet connection)
    if [[ "$CONNECTED" != "true" ]]; then
        SSID="${SSID:-Unknown/Ethernet}"
        BSSID="${BSSID:-none}"
        CHANNEL="${CHANNEL:-0}"
        BAND="${BAND:-none}"
        WIDTH_MHZ="${WIDTH_MHZ:-0}"
        RSSI_DBM="${RSSI_DBM:-0}"
        NOISE_DBM="${NOISE_DBM:-0}"
        SNR_DB="${SNR_DB:-0}"
        TX_RATE_MBPS="${TX_RATE_MBPS:-0}"
    fi

    # Network info
    LOCAL_IP=$(get_local_ip)
    PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "unknown")

    # VPN detection
    log "Detecting VPN status..."
    eval $(detect_vpn)

    # Ping/jitter test
    log "Running ping test for jitter..."
    eval $(run_ping_test)

    # Speed test
    log "Running speed test..."
    local speedtest_output=$(speedtest-cli --simple 2>&1)
    local speedtest_exit=$?

    if [[ $speedtest_exit -eq 0 ]]; then
        LATENCY_MS=$(echo "$speedtest_output" | grep "Ping:" | awk '{print $2}')
        DOWNLOAD_MBPS=$(echo "$speedtest_output" | grep "Download:" | awk '{print $2}')
        UPLOAD_MBPS=$(echo "$speedtest_output" | grep "Upload:" | awk '{print $2}')
        STATUS="success"
        log "Speed test completed - Down: ${DOWNLOAD_MBPS} Mbps, Up: ${UPLOAD_MBPS} Mbps"
    else
        LATENCY_MS="0"
        DOWNLOAD_MBPS="0"
        UPLOAD_MBPS="0"
        STATUS="failed"
        errors="speedtest_failed"
        log "Speed test failed: $speedtest_output"
    fi

    # Set defaults for any missing values
    LATENCY_MS=${LATENCY_MS:-0}
    DOWNLOAD_MBPS=${DOWNLOAD_MBPS:-0}
    UPLOAD_MBPS=${UPLOAD_MBPS:-0}
    JITTER_MS=${JITTER_MS:-0}
    JITTER_P50=${JITTER_P50:-0}
    JITTER_P95=${JITTER_P95:-0}
    PACKET_LOSS_PCT=${PACKET_LOSS_PCT:-0}

    ERRORS="$errors"

    # Build JSON payload
    local raw_payload=$(build_json_payload)
    # Escape quotes for CSV
    local csv_payload=$(echo "$raw_payload" | sed 's/"/\\"/g')

    # Append to CSV
    echo "$TIMESTAMP_UTC,$DEVICE_ID,$OS_VERSION,$VERSION,$TIMEZONE,$INTERFACE,$SSID,$BSSID,$BAND,$CHANNEL,$WIDTH_MHZ,$RSSI_DBM,$NOISE_DBM,$SNR_DB,$TX_RATE_MBPS,$LOCAL_IP,$PUBLIC_IP,$LATENCY_MS,$JITTER_MS,$JITTER_P50,$JITTER_P95,$PACKET_LOSS_PCT,$DOWNLOAD_MBPS,$UPLOAD_MBPS,$VPN_STATUS,$VPN_NAME,$ERRORS,\"$csv_payload\"" >> "$CSV_FILE"

    # Send to server if configured
    if [[ -n "$SERVER_URL" ]]; then
        log "Sending results to server..."
        curl -s -X POST "$SERVER_URL/api/results" \
            -H "Content-Type: application/json" \
            -d "$raw_payload" > /dev/null 2>&1 || log "Failed to send to server"
    fi

    # Print summary
    echo "=== Speed Test Results (v$VERSION) ==="
    echo "Time: $TIMESTAMP_UTC"
    echo "Device: $DEVICE_ID"
    echo "OS: macOS $OS_VERSION"
    echo "Network: $SSID ($INTERFACE)"
    echo "BSSID: $BSSID"
    echo "Band: $BAND | Channel: $CHANNEL | Width: ${WIDTH_MHZ}MHz"
    echo "Signal: ${RSSI_DBM}dBm | Noise: ${NOISE_DBM}dBm | SNR: ${SNR_DB}dB"
    echo "VPN: $VPN_NAME ($VPN_STATUS)"
    echo "Download: $DOWNLOAD_MBPS Mbps"
    echo "Upload: $UPLOAD_MBPS Mbps"
    echo "Latency: $LATENCY_MS ms"
    echo "Jitter: $JITTER_MS ms (P50: $JITTER_P50 | P95: $JITTER_P95)"
    echo "Packet Loss: $PACKET_LOSS_PCT%"
    echo "Status: $STATUS"
    echo "Results saved to: $CSV_FILE"

    log "Test completed"
}

# Run main collection
collect_metrics
