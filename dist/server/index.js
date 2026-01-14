const express = require('express');
const Database = require('better-sqlite3');
const cors = require('cors');
const path = require('path');
const rateLimit = require('express-rate-limit');

const app = express();
const PORT = process.env.PORT || 3000;

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
  message: { error: 'Too many requests, please try again later.' }
});

// Middleware
app.use(cors());
app.use(express.json({ limit: '1mb' }));
app.use(express.static(path.join(__dirname, 'public')));
app.use('/api/', limiter);

// Initialize SQLite database
const db = new Database(process.env.DB_PATH || './speed_monitor.db');

// Create tables with v2.0 schema
db.exec(`
  CREATE TABLE IF NOT EXISTS speed_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Identity
    device_id TEXT NOT NULL,
    user_id TEXT,
    hostname TEXT,

    -- Metadata
    timestamp_utc DATETIME NOT NULL,
    os_version TEXT,
    app_version TEXT,
    timezone TEXT,

    -- Network interface
    interface TEXT,
    local_ip TEXT,
    public_ip TEXT,

    -- WiFi details
    ssid TEXT,
    bssid TEXT,
    band TEXT,
    channel INTEGER DEFAULT 0,
    width_mhz INTEGER DEFAULT 0,
    rssi_dbm INTEGER DEFAULT 0,
    noise_dbm INTEGER DEFAULT 0,
    snr_db INTEGER DEFAULT 0,
    tx_rate_mbps REAL DEFAULT 0,

    -- Performance metrics
    latency_ms REAL DEFAULT 0,
    jitter_ms REAL DEFAULT 0,
    jitter_p50 REAL DEFAULT 0,
    jitter_p95 REAL DEFAULT 0,
    packet_loss_pct REAL DEFAULT 0,
    download_mbps REAL DEFAULT 0,
    upload_mbps REAL DEFAULT 0,

    -- VPN status
    vpn_status TEXT DEFAULT 'disconnected',
    vpn_name TEXT DEFAULT 'none',

    -- Status and errors
    status TEXT DEFAULT 'success',
    errors TEXT,

    -- Raw data
    raw_payload TEXT,

    -- Timestamps
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  -- Indexes for common queries
  CREATE INDEX IF NOT EXISTS idx_device_id ON speed_results(device_id);
  CREATE INDEX IF NOT EXISTS idx_timestamp ON speed_results(timestamp_utc);
  CREATE INDEX IF NOT EXISTS idx_ssid ON speed_results(ssid);
  CREATE INDEX IF NOT EXISTS idx_bssid ON speed_results(bssid);
  CREATE INDEX IF NOT EXISTS idx_vpn_status ON speed_results(vpn_status);
  CREATE INDEX IF NOT EXISTS idx_status ON speed_results(status);

  -- Composite index for time-series queries
  CREATE INDEX IF NOT EXISTS idx_device_time ON speed_results(device_id, timestamp_utc);
`);

// API: Submit speed test result (v2.0)
app.post('/api/results', (req, res) => {
  const data = req.body;

  if (!data.device_id) {
    return res.status(400).json({ error: 'device_id is required' });
  }

  try {
    const stmt = db.prepare(`
      INSERT INTO speed_results (
        device_id, user_id, hostname, timestamp_utc, os_version, app_version, timezone,
        interface, local_ip, public_ip,
        ssid, bssid, band, channel, width_mhz, rssi_dbm, noise_dbm, snr_db, tx_rate_mbps,
        latency_ms, jitter_ms, jitter_p50, jitter_p95, packet_loss_pct, download_mbps, upload_mbps,
        vpn_status, vpn_name, status, errors, raw_payload
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?,
        ?, ?, ?,
        ?, ?, ?, ?, ?, ?, ?, ?, ?,
        ?, ?, ?, ?, ?, ?, ?,
        ?, ?, ?, ?, ?
      )
    `);

    const result = stmt.run(
      data.device_id,
      data.user_id || data.device_id,
      data.hostname || null,
      data.timestamp_utc || new Date().toISOString(),
      data.os_version || null,
      data.app_version || null,
      data.timezone || null,
      data.interface || null,
      data.local_ip || null,
      data.public_ip || null,
      data.ssid || null,
      data.bssid || null,
      data.band || null,
      data.channel || 0,
      data.width_mhz || 0,
      data.rssi_dbm || 0,
      data.noise_dbm || 0,
      data.snr_db || 0,
      data.tx_rate_mbps || 0,
      data.latency_ms || 0,
      data.jitter_ms || 0,
      data.jitter_p50 || 0,
      data.jitter_p95 || 0,
      data.packet_loss_pct || 0,
      data.download_mbps || 0,
      data.upload_mbps || 0,
      data.vpn_status || 'disconnected',
      data.vpn_name || 'none',
      data.status || 'success',
      data.errors || null,
      typeof data === 'object' ? JSON.stringify(data) : null
    );

    res.json({ success: true, id: result.lastInsertRowid });
  } catch (err) {
    console.error('Error inserting result:', err);
    res.status(500).json({ error: 'Failed to save result' });
  }
});

// API: Get all results (with pagination)
app.get('/api/results', (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 100, 1000);
  const offset = parseInt(req.query.offset) || 0;
  const device_id = req.query.device_id;
  const ssid = req.query.ssid;
  const vpn_status = req.query.vpn_status;

  try {
    let query = 'SELECT * FROM speed_results WHERE 1=1';
    let params = [];

    if (device_id) {
      query += ' AND device_id = ?';
      params.push(device_id);
    }
    if (ssid) {
      query += ' AND ssid = ?';
      params.push(ssid);
    }
    if (vpn_status) {
      query += ' AND vpn_status = ?';
      params.push(vpn_status);
    }

    query += ' ORDER BY timestamp_utc DESC LIMIT ? OFFSET ?';
    params.push(limit, offset);

    const results = db.prepare(query).all(...params);
    res.json(results);
  } catch (err) {
    console.error('Error fetching results:', err);
    res.status(500).json({ error: 'Failed to fetch results' });
  }
});

// API: Get aggregated stats
app.get('/api/stats', (req, res) => {
  try {
    // Overall stats
    const overall = db.prepare(`
      SELECT
        COUNT(*) as total_tests,
        COUNT(DISTINCT device_id) as total_devices,
        ROUND(AVG(download_mbps), 2) as avg_download,
        ROUND(AVG(upload_mbps), 2) as avg_upload,
        ROUND(AVG(latency_ms), 2) as avg_latency,
        ROUND(AVG(jitter_ms), 2) as avg_jitter,
        ROUND(AVG(packet_loss_pct), 2) as avg_packet_loss,
        ROUND(MIN(download_mbps), 2) as min_download,
        ROUND(MAX(download_mbps), 2) as max_download
      FROM speed_results
      WHERE status = 'success'
    `).get();

    // Per-device stats
    const perDevice = db.prepare(`
      SELECT
        device_id,
        MAX(hostname) as hostname,
        MAX(os_version) as os_version,
        MAX(app_version) as app_version,
        COUNT(*) as test_count,
        ROUND(AVG(download_mbps), 2) as avg_download,
        ROUND(AVG(upload_mbps), 2) as avg_upload,
        ROUND(AVG(latency_ms), 2) as avg_latency,
        ROUND(AVG(jitter_ms), 2) as avg_jitter,
        MAX(timestamp_utc) as last_test,
        MAX(vpn_status) as vpn_status,
        MAX(vpn_name) as vpn_name
      FROM speed_results
      WHERE status = 'success'
      GROUP BY device_id
      ORDER BY last_test DESC
    `).all();

    // Hourly trends (last 24 hours)
    const hourly = db.prepare(`
      SELECT
        strftime('%Y-%m-%d %H:00', timestamp_utc) as hour,
        ROUND(AVG(download_mbps), 2) as avg_download,
        ROUND(AVG(upload_mbps), 2) as avg_upload,
        ROUND(AVG(jitter_ms), 2) as avg_jitter,
        COUNT(*) as test_count
      FROM speed_results
      WHERE status = 'success'
        AND timestamp_utc > datetime('now', '-24 hours')
      GROUP BY hour
      ORDER BY hour
    `).all();

    res.json({ overall, perDevice, hourly });
  } catch (err) {
    console.error('Error fetching stats:', err);
    res.status(500).json({ error: 'Failed to fetch stats' });
  }
});

// API: WiFi/Access Point statistics
app.get('/api/stats/wifi', (req, res) => {
  try {
    // Stats by access point (BSSID)
    const byAccessPoint = db.prepare(`
      SELECT
        bssid,
        MAX(ssid) as ssid,
        MAX(band) as band,
        MAX(channel) as channel,
        COUNT(*) as test_count,
        COUNT(DISTINCT device_id) as device_count,
        ROUND(AVG(download_mbps), 2) as avg_download,
        ROUND(AVG(upload_mbps), 2) as avg_upload,
        ROUND(AVG(rssi_dbm), 0) as avg_rssi,
        ROUND(AVG(jitter_ms), 2) as avg_jitter,
        ROUND(AVG(packet_loss_pct), 2) as avg_packet_loss
      FROM speed_results
      WHERE status = 'success' AND bssid IS NOT NULL AND bssid != 'none'
      GROUP BY bssid
      ORDER BY test_count DESC
    `).all();

    // Stats by SSID
    const bySSID = db.prepare(`
      SELECT
        ssid,
        COUNT(*) as test_count,
        COUNT(DISTINCT device_id) as device_count,
        COUNT(DISTINCT bssid) as ap_count,
        ROUND(AVG(download_mbps), 2) as avg_download,
        ROUND(AVG(upload_mbps), 2) as avg_upload,
        ROUND(AVG(rssi_dbm), 0) as avg_rssi
      FROM speed_results
      WHERE status = 'success' AND ssid IS NOT NULL
      GROUP BY ssid
      ORDER BY test_count DESC
    `).all();

    // Band distribution
    const bandDistribution = db.prepare(`
      SELECT
        band,
        COUNT(*) as count,
        ROUND(AVG(download_mbps), 2) as avg_download
      FROM speed_results
      WHERE status = 'success' AND band IS NOT NULL AND band != 'none'
      GROUP BY band
    `).all();

    res.json({ byAccessPoint, bySSID, bandDistribution });
  } catch (err) {
    console.error('Error fetching WiFi stats:', err);
    res.status(500).json({ error: 'Failed to fetch WiFi stats' });
  }
});

// API: VPN statistics
app.get('/api/stats/vpn', (req, res) => {
  try {
    // VPN usage distribution
    const distribution = db.prepare(`
      SELECT
        vpn_status,
        vpn_name,
        COUNT(*) as count,
        ROUND(AVG(download_mbps), 2) as avg_download,
        ROUND(AVG(upload_mbps), 2) as avg_upload,
        ROUND(AVG(latency_ms), 2) as avg_latency,
        ROUND(AVG(jitter_ms), 2) as avg_jitter
      FROM speed_results
      WHERE status = 'success'
      GROUP BY vpn_status, vpn_name
      ORDER BY count DESC
    `).all();

    // VPN vs non-VPN comparison
    const comparison = db.prepare(`
      SELECT
        CASE WHEN vpn_status = 'connected' THEN 'VPN On' ELSE 'VPN Off' END as mode,
        COUNT(*) as test_count,
        ROUND(AVG(download_mbps), 2) as avg_download,
        ROUND(AVG(upload_mbps), 2) as avg_upload,
        ROUND(AVG(latency_ms), 2) as avg_latency,
        ROUND(AVG(jitter_ms), 2) as avg_jitter,
        ROUND(AVG(packet_loss_pct), 2) as avg_packet_loss
      FROM speed_results
      WHERE status = 'success'
      GROUP BY mode
    `).all();

    res.json({ distribution, comparison });
  } catch (err) {
    console.error('Error fetching VPN stats:', err);
    res.status(500).json({ error: 'Failed to fetch VPN stats' });
  }
});

// API: Jitter distribution
app.get('/api/stats/jitter', (req, res) => {
  try {
    const distribution = db.prepare(`
      SELECT
        CASE
          WHEN jitter_ms < 5 THEN '< 5ms'
          WHEN jitter_ms < 10 THEN '5-10ms'
          WHEN jitter_ms < 20 THEN '10-20ms'
          WHEN jitter_ms < 50 THEN '20-50ms'
          ELSE '> 50ms'
        END as bucket,
        COUNT(*) as count,
        ROUND(AVG(download_mbps), 2) as avg_download
      FROM speed_results
      WHERE status = 'success' AND jitter_ms IS NOT NULL
      GROUP BY bucket
      ORDER BY
        CASE bucket
          WHEN '< 5ms' THEN 1
          WHEN '5-10ms' THEN 2
          WHEN '10-20ms' THEN 3
          WHEN '20-50ms' THEN 4
          ELSE 5
        END
    `).all();

    // Problem devices (high jitter)
    const problemDevices = db.prepare(`
      SELECT
        device_id,
        MAX(hostname) as hostname,
        COUNT(*) as test_count,
        ROUND(AVG(jitter_ms), 2) as avg_jitter,
        ROUND(AVG(packet_loss_pct), 2) as avg_packet_loss,
        MAX(timestamp_utc) as last_test
      FROM speed_results
      WHERE status = 'success'
      GROUP BY device_id
      HAVING AVG(jitter_ms) > 20 OR AVG(packet_loss_pct) > 1
      ORDER BY avg_jitter DESC
      LIMIT 20
    `).all();

    res.json({ distribution, problemDevices });
  } catch (err) {
    console.error('Error fetching jitter stats:', err);
    res.status(500).json({ error: 'Failed to fetch jitter stats' });
  }
});

// API: Device health
app.get('/api/devices/:device_id/health', (req, res) => {
  const { device_id } = req.params;

  try {
    const health = db.prepare(`
      SELECT
        device_id,
        MAX(hostname) as hostname,
        MAX(os_version) as os_version,
        MAX(app_version) as app_version,
        COUNT(*) as total_tests,
        SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) as successful_tests,
        ROUND(AVG(CASE WHEN status = 'success' THEN download_mbps END), 2) as avg_download,
        ROUND(AVG(CASE WHEN status = 'success' THEN upload_mbps END), 2) as avg_upload,
        ROUND(AVG(CASE WHEN status = 'success' THEN jitter_ms END), 2) as avg_jitter,
        ROUND(AVG(CASE WHEN status = 'success' THEN packet_loss_pct END), 2) as avg_packet_loss,
        MAX(timestamp_utc) as last_seen,
        MAX(vpn_status) as current_vpn_status,
        MAX(vpn_name) as current_vpn_name,
        MAX(ssid) as current_ssid
      FROM speed_results
      WHERE device_id = ?
    `).get(device_id);

    // Recent tests
    const recentTests = db.prepare(`
      SELECT *
      FROM speed_results
      WHERE device_id = ?
      ORDER BY timestamp_utc DESC
      LIMIT 20
    `).all(device_id);

    res.json({ health, recentTests });
  } catch (err) {
    console.error('Error fetching device health:', err);
    res.status(500).json({ error: 'Failed to fetch device health' });
  }
});

// API: Get device's results
app.get('/api/results/:device_id', (req, res) => {
  const { device_id } = req.params;
  const limit = Math.min(parseInt(req.query.limit) || 50, 500);

  try {
    const results = db.prepare(`
      SELECT * FROM speed_results
      WHERE device_id = ?
      ORDER BY timestamp_utc DESC
      LIMIT ?
    `).all(device_id, limit);

    res.json(results);
  } catch (err) {
    console.error('Error fetching device results:', err);
    res.status(500).json({ error: 'Failed to fetch results' });
  }
});

// Serve dashboard
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'dashboard.html'));
});

// Health check
app.get('/health', (req, res) => {
  try {
    const count = db.prepare('SELECT COUNT(*) as count FROM speed_results').get();
    res.json({
      status: 'ok',
      timestamp: new Date().toISOString(),
      version: '2.0.0',
      total_results: count.count
    });
  } catch (err) {
    res.status(500).json({ status: 'error', error: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`Speed Monitor Server v2.0.0 running on port ${PORT}`);
  console.log(`Dashboard: http://localhost:${PORT}`);
  console.log(`API: http://localhost:${PORT}/api`);
});
