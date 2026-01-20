#!/bin/bash
#
# Test Speed Monitor Installation
# Verifies that the .pkg installed correctly
#
# Usage: ./test-installation.sh
#

echo "=== Speed Monitor Installation Test ==="
echo ""

ERRORS=0
WARNINGS=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ERRORS=$((ERRORS + 1))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

info() {
    echo "ℹ $1"
}

echo "1. Checking Global Installation..."
echo ""

# Check global installation
if [ -d "/usr/local/speedmonitor" ]; then
    pass "Global installation directory exists"
else
    fail "Global installation directory missing: /usr/local/speedmonitor"
fi

if [ -f "/usr/local/speedmonitor/bin/speed_monitor.sh" ]; then
    pass "Main script installed"
else
    fail "Main script missing: /usr/local/speedmonitor/bin/speed_monitor.sh"
fi

if [ -x "/usr/local/speedmonitor/bin/speed_monitor.sh" ]; then
    pass "Main script is executable"
else
    fail "Main script is not executable"
fi

if [ -f "/usr/local/speedmonitor/lib/config.sh" ]; then
    pass "Configuration file exists"
    # Show server URL
    SERVER_URL=$(grep "SERVER_URL=" /usr/local/speedmonitor/lib/config.sh | cut -d'"' -f2)
    info "Server URL: $SERVER_URL"
else
    warn "Configuration file missing"
fi

echo ""
echo "2. Checking Dependencies..."
echo ""

# Check Homebrew
if command -v brew &> /dev/null; then
    pass "Homebrew installed: $(brew --version | head -1)"
else
    fail "Homebrew not found"
fi

# Check speedtest-cli
if command -v speedtest-cli &> /dev/null; then
    SPEEDTEST_VERSION=$(speedtest-cli --version 2>&1 | head -1)
    pass "speedtest-cli installed: $SPEEDTEST_VERSION"
else
    fail "speedtest-cli not found"
fi

# Check Swift compiler
if command -v swiftc &> /dev/null; then
    SWIFT_VERSION=$(swiftc --version | head -1)
    pass "Swift compiler available: $SWIFT_VERSION"
else
    warn "Swift compiler not available (optional)"
fi

# Check Swift helper
if [ -f "/usr/local/speedmonitor/bin/wifi_info" ]; then
    if [ -x "/usr/local/speedmonitor/bin/wifi_info" ]; then
        pass "Swift WiFi helper compiled"
    else
        warn "Swift WiFi helper not executable"
    fi
else
    warn "Swift WiFi helper not compiled (will use fallback)"
fi

echo ""
echo "3. Checking User Installation..."
echo ""

# Check user directories
if [ -d "$HOME/.local/share/nkspeedtest" ]; then
    pass "User data directory exists"
else
    fail "User data directory missing: ~/.local/share/nkspeedtest"
fi

if [ -d "$HOME/.config/nkspeedtest" ]; then
    pass "User config directory exists"
else
    fail "User config directory missing: ~/.config/nkspeedtest"
fi

# Check device ID
if [ -f "$HOME/.config/nkspeedtest/device_id" ]; then
    DEVICE_ID=$(cat "$HOME/.config/nkspeedtest/device_id")
    pass "Device ID generated: $DEVICE_ID"
else
    fail "Device ID not generated"
fi

# Check user email
if [ -f "$HOME/.config/nkspeedtest/user_email" ]; then
    USER_EMAIL=$(cat "$HOME/.config/nkspeedtest/user_email")
    pass "User email configured: $USER_EMAIL"
else
    warn "User email not configured (optional)"
fi

echo ""
echo "4. Checking LaunchAgent..."
echo ""

# Check LaunchAgent plist
if [ -f "$HOME/Library/LaunchAgents/com.speedmonitor.plist" ]; then
    pass "LaunchAgent plist exists"
else
    fail "LaunchAgent plist missing: ~/Library/LaunchAgents/com.speedmonitor.plist"
fi

# Check if LaunchAgent is loaded
if launchctl list | grep -q "com.speedmonitor"; then
    pass "LaunchAgent is loaded"

    # Get status
    STATUS=$(launchctl list | grep "com.speedmonitor")
    info "Status: $STATUS"
else
    fail "LaunchAgent is not loaded"
fi

echo ""
echo "5. Checking Menu Bar App..."
echo ""

# Check SpeedMonitor.app
APP_FOUND=false
if [ -d "$HOME/Applications/SpeedMonitor.app" ]; then
    pass "SpeedMonitor.app installed (user)"
    APP_FOUND=true
elif [ -d "/Applications/SpeedMonitor.app" ]; then
    pass "SpeedMonitor.app installed (system)"
    APP_FOUND=true
else
    warn "SpeedMonitor.app not found (optional)"
fi

if $APP_FOUND; then
    # Check if running
    if pgrep -x "SpeedMonitor" > /dev/null; then
        pass "SpeedMonitor.app is running"
    else
        info "SpeedMonitor.app is not running (launch it manually)"
    fi
fi

echo ""
echo "6. Checking Data Collection..."
echo ""

# Check CSV file
if [ -f "$HOME/.local/share/nkspeedtest/speed_log.csv" ]; then
    LINE_COUNT=$(wc -l < "$HOME/.local/share/nkspeedtest/speed_log.csv")
    if [ "$LINE_COUNT" -gt 1 ]; then
        pass "CSV file exists with $LINE_COUNT lines"

        # Show last test
        LAST_TEST=$(tail -1 "$HOME/.local/share/nkspeedtest/speed_log.csv" | cut -d',' -f1)
        info "Last test: $LAST_TEST"
    else
        warn "CSV file exists but no data yet (test may be running)"
    fi
else
    warn "CSV file not created yet (initial test may still be running)"
fi

# Check logs
if [ -f "$HOME/.local/share/nkspeedtest/speed_monitor.log" ]; then
    pass "Speed monitor log exists"

    # Check for recent activity
    if [ -f "$HOME/.local/share/nkspeedtest/speed_monitor.log" ]; then
        LAST_LOG=$(tail -1 "$HOME/.local/share/nkspeedtest/speed_monitor.log" 2>/dev/null)
        info "Last log: $LAST_LOG"
    fi
else
    warn "Speed monitor log not created yet"
fi

# Check LaunchAgent logs
if [ -f "$HOME/.local/share/nkspeedtest/launchd_stdout.log" ]; then
    pass "LaunchAgent stdout log exists"
else
    warn "LaunchAgent stdout log not created yet"
fi

if [ -f "$HOME/.local/share/nkspeedtest/launchd_stderr.log" ]; then
    # Check for errors
    if [ -s "$HOME/.local/share/nkspeedtest/launchd_stderr.log" ]; then
        warn "LaunchAgent stderr log has content (check for errors)"
        info "View errors: tail ~/.local/share/nkspeedtest/launchd_stderr.log"
    else
        pass "LaunchAgent stderr log is empty (no errors)"
    fi
else
    info "LaunchAgent stderr log not created yet"
fi

echo ""
echo "7. Testing Connectivity..."
echo ""

# Test server connectivity
if [ -n "$SERVER_URL" ]; then
    if curl -s --max-time 5 "${SERVER_URL}/api/version" > /dev/null 2>&1; then
        pass "Server is reachable: $SERVER_URL"

        # Get server version
        SERVER_VERSION=$(curl -s --max-time 5 "${SERVER_URL}/api/version" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$SERVER_VERSION" ]; then
            info "Server version: $SERVER_VERSION"
        fi
    else
        fail "Cannot reach server: $SERVER_URL"
    fi
else
    warn "Server URL not configured"
fi

# Test internet connectivity
if curl -s --max-time 5 https://www.google.com > /dev/null 2>&1; then
    pass "Internet connectivity OK"
else
    fail "No internet connectivity"
fi

echo ""
echo "8. Checking Installation Logs..."
echo ""

# Check system installation log
if [ -f "/var/log/speedmonitor-install.log" ]; then
    pass "Installation log exists"

    # Check for errors in log
    ERROR_COUNT=$(grep -c "ERROR:" /var/log/speedmonitor-install.log 2>/dev/null || echo "0")
    WARNING_COUNT=$(grep -c "WARNING:" /var/log/speedmonitor-install.log 2>/dev/null || echo "0")

    if [ "$ERROR_COUNT" -gt 0 ]; then
        warn "Installation log contains $ERROR_COUNT errors"
        info "View errors: sudo grep ERROR /var/log/speedmonitor-install.log"
    else
        pass "No errors in installation log"
    fi

    if [ "$WARNING_COUNT" -gt 0 ]; then
        info "Installation log contains $WARNING_COUNT warnings (may be normal)"
    fi
else
    warn "Installation log not found: /var/log/speedmonitor-install.log"
fi

echo ""
echo "=== Test Summary ==="
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    echo ""
    echo "Speed Monitor is installed and running correctly."
    echo ""
    echo "Next steps:"
    echo "1. Grant Location Services permission:"
    echo "   - Open SpeedMonitor.app from Applications"
    echo "   - Click Settings → Grant Permission"
    echo "2. View dashboard: $SERVER_URL"
    echo "3. Check menu bar for SpeedMonitor icon"
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}Tests passed with $WARNINGS warning(s)${NC}"
    echo ""
    echo "Speed Monitor is installed but some optional features may not be available."
    echo "Check warnings above for details."
else
    echo -e "${RED}Tests failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo "Some components are not installed correctly."
    echo "Review errors above and check logs:"
    echo "  - Installation: /var/log/speedmonitor-install.log"
    echo "  - Runtime: ~/.local/share/nkspeedtest/speed_monitor.log"
    echo "  - LaunchAgent: ~/.local/share/nkspeedtest/launchd_stderr.log"
fi

echo ""
echo "Useful commands:"
echo "  View logs:       tail -f ~/.local/share/nkspeedtest/speed_monitor.log"
echo "  Run manual test: ~/.local/bin/speed_monitor.sh"
echo "  Check status:    launchctl list | grep speedmonitor"
echo "  View data:       tail ~/.local/share/nkspeedtest/speed_log.csv"
echo ""

exit $ERRORS
