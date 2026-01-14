# Home Internet Monitoring Project

## Overview
This project monitors home internet speed and contains configuration for the ACT Fibernet connection with a TP-Link Archer C5 v4 router.

## Files

| File | Purpose |
|------|---------|
| `speed_monitor.sh` | Bash script that runs speed tests using `speedtest-cli` |
| `speed_log.csv` | CSV log of all speed test results |
| `speed_monitor.log` | Script execution logs |
| `com.speedmonitor.plist` | macOS launchd config (runs every 10 minutes) |
| `credentials.md` | Router and account credentials (sensitive) |
| `launchd_stdout.log` | launchd standard output |
| `launchd_stderr.log` | launchd error output |

## Speed Monitor Setup

### Dependencies
- `speedtest-cli` (installed via Homebrew: `brew install speedtest-cli`)

### launchd Installation
```bash
# Copy plist to LaunchAgents
cp com.speedmonitor.plist ~/Library/LaunchAgents/

# Load the job
launchctl load ~/Library/LaunchAgents/com.speedmonitor.plist

# Verify it's running
launchctl list | grep speedmonitor
```

### Known Issue: macOS Security
The script may fail with "Operation not permitted" due to macOS security. Fix by granting Full Disk Access to `/bin/bash`:
1. System Settings → Privacy & Security → Full Disk Access
2. Add `/bin/bash`
3. Restart the launchd job

### CSV Columns
`timestamp, date, time, network_ssid, download_mbps, upload_mbps, ping_ms, server, external_ip, signal_strength, noise, channel, status`

## Router Configuration

### Hardware
- **Model:** TP-Link Archer C5 v4
- **Firmware:** 3.16.0 0.9.1 v6015.0 Build 240806 Rel.22720n
- **ISP:** ACT Fibernet

### Optimized Settings
| Setting | Value | Reason |
|---------|-------|--------|
| 2.4GHz Encryption | AES | Faster than TKIP |
| 2.4GHz Mode | 802.11g/n | Removed slow 802.11b |
| 5GHz Encryption | AES | Faster than TKIP |
| Band Steering | Enabled | Auto-switches devices to best band |

### Known Router Bug
**Error 7503: "The input SSID already exists"** - Firmware bug when saving wireless settings. Workaround: Slightly modify the SSID before saving.

### TR-069 (CWMP)
Router is remotely managed by ACT Fibernet via TR-069. Settings may be overwritten by ISP's Auto Configuration Server (ACS). Contact ACT support to persist custom settings.

## Useful Commands

```bash
# View latest speed logs
tail -20 speed_log.csv

# Check if launchd job is running
launchctl list | grep speedmonitor

# Manually run speed test
./speed_monitor.sh

# Restart launchd job
launchctl unload ~/Library/LaunchAgents/com.speedmonitor.plist
launchctl load ~/Library/LaunchAgents/com.speedmonitor.plist
```

## ACT Fibernet Account
- Account Number: See credentials.md
- Router Login: http://192.168.0.1/
