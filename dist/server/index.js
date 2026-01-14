const express = require('express');
const Database = require('better-sqlite3');
const cors = require('cors');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Initialize SQLite database
const db = new Database(process.env.DB_PATH || './speed_monitor.db');

// Create tables
db.exec(`
  CREATE TABLE IF NOT EXISTS speed_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    hostname TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    download_mbps REAL,
    upload_mbps REAL,
    ping_ms REAL,
    network_ssid TEXT,
    external_ip TEXT,
    status TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_user_id ON speed_results(user_id);
  CREATE INDEX IF NOT EXISTS idx_timestamp ON speed_results(timestamp);
`);

// API: Submit speed test result
app.post('/api/results', (req, res) => {
  const {
    user_id,
    hostname,
    timestamp,
    download_mbps,
    upload_mbps,
    ping_ms,
    network_ssid,
    external_ip,
    status
  } = req.body;

  if (!user_id) {
    return res.status(400).json({ error: 'user_id is required' });
  }

  try {
    const stmt = db.prepare(`
      INSERT INTO speed_results
      (user_id, hostname, timestamp, download_mbps, upload_mbps, ping_ms, network_ssid, external_ip, status)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    const result = stmt.run(
      user_id,
      hostname || null,
      timestamp || new Date().toISOString(),
      download_mbps || 0,
      upload_mbps || 0,
      ping_ms || 0,
      network_ssid || null,
      external_ip || null,
      status || 'success'
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
  const user_id = req.query.user_id;

  try {
    let query = 'SELECT * FROM speed_results';
    let params = [];

    if (user_id) {
      query += ' WHERE user_id = ?';
      params.push(user_id);
    }

    query += ' ORDER BY timestamp DESC LIMIT ? OFFSET ?';
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
        COUNT(DISTINCT user_id) as total_users,
        ROUND(AVG(download_mbps), 2) as avg_download,
        ROUND(AVG(upload_mbps), 2) as avg_upload,
        ROUND(AVG(ping_ms), 2) as avg_ping,
        ROUND(MIN(download_mbps), 2) as min_download,
        ROUND(MAX(download_mbps), 2) as max_download
      FROM speed_results
      WHERE status = 'success'
    `).get();

    // Per-user stats
    const perUser = db.prepare(`
      SELECT
        user_id,
        hostname,
        COUNT(*) as test_count,
        ROUND(AVG(download_mbps), 2) as avg_download,
        ROUND(AVG(upload_mbps), 2) as avg_upload,
        ROUND(AVG(ping_ms), 2) as avg_ping,
        MAX(timestamp) as last_test
      FROM speed_results
      WHERE status = 'success'
      GROUP BY user_id
      ORDER BY avg_download DESC
    `).all();

    // Recent results (last 24 hours, hourly avg)
    const hourly = db.prepare(`
      SELECT
        strftime('%Y-%m-%d %H:00', timestamp) as hour,
        ROUND(AVG(download_mbps), 2) as avg_download,
        ROUND(AVG(upload_mbps), 2) as avg_upload,
        COUNT(*) as test_count
      FROM speed_results
      WHERE status = 'success'
        AND timestamp > datetime('now', '-24 hours')
      GROUP BY hour
      ORDER BY hour
    `).all();

    res.json({
      overall,
      perUser,
      hourly
    });
  } catch (err) {
    console.error('Error fetching stats:', err);
    res.status(500).json({ error: 'Failed to fetch stats' });
  }
});

// API: Get user's results
app.get('/api/results/:user_id', (req, res) => {
  const { user_id } = req.params;
  const limit = Math.min(parseInt(req.query.limit) || 50, 500);

  try {
    const results = db.prepare(`
      SELECT * FROM speed_results
      WHERE user_id = ?
      ORDER BY timestamp DESC
      LIMIT ?
    `).all(user_id, limit);

    res.json(results);
  } catch (err) {
    console.error('Error fetching user results:', err);
    res.status(500).json({ error: 'Failed to fetch results' });
  }
});

// Serve dashboard
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'dashboard.html'));
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.listen(PORT, () => {
  console.log(`Speed Monitor Server running on port ${PORT}`);
  console.log(`Dashboard: http://localhost:${PORT}`);
  console.log(`API: http://localhost:${PORT}/api`);
});
