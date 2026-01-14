#!/bin/bash

# Serve the speed monitor dashboard locally
# This script starts a local HTTP server and opens the dashboard

PORT=8765
DIR="/Users/kishore/Desktop/Claude-experiments/home-internet"
URL="http://localhost:$PORT/dashboard.html"

# Check if server is already running on this port
if lsof -i :$PORT > /dev/null 2>&1; then
    echo "Server already running on port $PORT"
    open "$URL"
    exit 0
fi

# Start Python HTTP server in background
cd "$DIR"
python3 -m http.server $PORT > /dev/null 2>&1 &
SERVER_PID=$!

# Wait a moment for server to start
sleep 0.5

# Open dashboard in default browser
open "$URL"

echo "Dashboard server started (PID: $SERVER_PID)"
echo "URL: $URL"
echo "To stop: kill $SERVER_PID"
