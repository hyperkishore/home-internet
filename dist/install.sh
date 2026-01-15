#!/bin/bash
# Speed Monitor v3.0.0 - One-line installer for employees
# Usage: curl -fsSL https://raw.githubusercontent.com/hyperkishore/home-internet/main/dist/install.sh | bash

set -e

SERVER_URL="https://home-internet-production.up.railway.app"
SCRIPT_DIR="$HOME/.local/share/nkspeedtest"
CONFIG_DIR="$HOME/.config/nkspeedtest"
BIN_DIR="$HOME/.local/bin"
PLIST_NAME="com.speedmonitor.plist"

echo "=== Speed Monitor v3.0.0 Installer ==="
echo ""

# Create directories
mkdir -p "$SCRIPT_DIR" "$BIN_DIR" "$CONFIG_DIR"

# Collect user email
echo "Please enter your Hyperverge email address:"
read -p "Email: " USER_EMAIL

# Validate email format (basic check)
if [[ ! "$USER_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "Warning: Email format looks invalid, but continuing anyway..."
fi

# Store email
echo "$USER_EMAIL" > "$CONFIG_DIR/user_email"
echo "Email saved: $USER_EMAIL"
echo ""

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install speedtest-cli
if ! command -v speedtest-cli &> /dev/null; then
    echo "Installing speedtest-cli..."
    brew install speedtest-cli
fi

# Download the speed monitor script
echo "Downloading speed monitor script..."
curl -fsSL "https://raw.githubusercontent.com/hyperkishore/home-internet/main/speed_monitor.sh" -o "$BIN_DIR/speed_monitor.sh"
chmod +x "$BIN_DIR/speed_monitor.sh"

# Download wifi_info Swift helper (pre-compiled or compile if needed)
echo "Setting up WiFi helper..."
if [[ -f "/opt/homebrew/bin/wifi_info" ]]; then
    ln -sf "/opt/homebrew/bin/wifi_info" "$BIN_DIR/wifi_info"
else
    # Download and compile
    curl -fsSL "https://raw.githubusercontent.com/hyperkishore/home-internet/main/dist/src/wifi_info.swift" -o "$SCRIPT_DIR/wifi_info.swift"
    swiftc -O -o "$BIN_DIR/wifi_info" "$SCRIPT_DIR/wifi_info.swift" -framework CoreWLAN -framework Foundation 2>/dev/null || echo "WiFi helper compilation skipped (will use fallback)"
fi

# Create launchd plist
echo "Creating launchd service..."
cat > "$HOME/Library/LaunchAgents/$PLIST_NAME" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.speedmonitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN_DIR/speed_monitor.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$SCRIPT_DIR/launchd_stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$SCRIPT_DIR/launchd_stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>SPEED_MONITOR_SERVER</key>
        <string>$SERVER_URL</string>
    </dict>
</dict>
</plist>
EOF

# Unload existing service if present
launchctl unload "$HOME/Library/LaunchAgents/$PLIST_NAME" 2>/dev/null || true

# Load the service
launchctl load "$HOME/Library/LaunchAgents/$PLIST_NAME"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Speed Monitor is now running and will:"
echo "  - Run a speed test every 10 minutes"
echo "  - Upload results to: $SERVER_URL"
echo "  - Store local logs in: $SCRIPT_DIR"
echo ""
echo "View the dashboard: $SERVER_URL"
echo ""
echo "Commands:"
echo "  Run test now:  SPEED_MONITOR_SERVER=$SERVER_URL $BIN_DIR/speed_monitor.sh"
echo "  View logs:     tail -f $SCRIPT_DIR/launchd_stdout.log"
echo "  Stop service:  launchctl unload ~/Library/LaunchAgents/$PLIST_NAME"
echo ""
