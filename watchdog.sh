#!/bin/bash

# Watchdog script for internet speed monitoring system
# Ensures SwiftBar, speed monitor, and dashboard server are always running

LOG_FILE="$HOME/.local/share/nkspeedtest/watchdog.log"
SPEED_MONITOR_PLIST="com.speedmonitor"
DASHBOARD_PLIST="com.speedmonitor.dashboard"
SWIFTBAR_APP="/Applications/SwiftBar.app"
SPEED_CSV="$HOME/.local/share/nkspeedtest/speed_log.csv"
SPEED_MONITOR_SCRIPT="$HOME/.local/bin/speed_monitor.sh"
STALE_THRESHOLD_MINUTES=30

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Check and start SwiftBar
check_swiftbar() {
    if ! pgrep -x "SwiftBar" > /dev/null; then
        log "SwiftBar not running - starting..."
        open -a "$SWIFTBAR_APP"
        sleep 2
        if pgrep -x "SwiftBar" > /dev/null; then
            log "SwiftBar started successfully"
        else
            log "ERROR: Failed to start SwiftBar"
        fi
    fi
}

# Check and load speed monitor launchd job
check_speed_monitor() {
    if ! launchctl list | grep -q "$SPEED_MONITOR_PLIST"; then
        log "Speed monitor launchd job not loaded - loading..."
        launchctl load "$HOME/Library/LaunchAgents/${SPEED_MONITOR_PLIST}.plist" 2>/dev/null
        if launchctl list | grep -q "$SPEED_MONITOR_PLIST"; then
            log "Speed monitor loaded successfully"
        else
            log "ERROR: Failed to load speed monitor"
        fi
    fi
}

# Check and load dashboard server launchd job
check_dashboard_server() {
    if ! launchctl list | grep -q "$DASHBOARD_PLIST"; then
        log "Dashboard server not loaded - loading..."
        launchctl load "$HOME/Library/LaunchAgents/${DASHBOARD_PLIST}.plist" 2>/dev/null
        if launchctl list | grep -q "$DASHBOARD_PLIST"; then
            log "Dashboard server loaded successfully"
        else
            log "ERROR: Failed to load dashboard server"
        fi
    fi
}

# Check if speed data is stale and trigger a test if needed
check_data_freshness() {
    if [[ -f "$SPEED_CSV" ]]; then
        last_modified=$(stat -f %m "$SPEED_CSV")
        current_time=$(date +%s)
        age_minutes=$(( (current_time - last_modified) / 60 ))

        if [[ $age_minutes -gt $STALE_THRESHOLD_MINUTES ]]; then
            log "Speed data is stale (${age_minutes} min old) - triggering test..."
            "$SPEED_MONITOR_SCRIPT" &
        fi
    else
        log "Speed CSV not found - triggering initial test..."
        "$SPEED_MONITOR_SCRIPT" &
    fi
}

# Main execution
log "Watchdog check started"
check_swiftbar
check_speed_monitor
check_dashboard_server
check_data_freshness
log "Watchdog check completed"
