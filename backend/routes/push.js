const express    = require('express');
const admin      = require('firebase-admin');
const db         = require('../db');
const { requireAuth } = require('../middleware/jwt');

const router = express.Router();

// Firebase Admin einmalig initialisieren
if (!admin.apps.length) {
  const serviceAccount = require(process.env.FIREBASE_SERVICE_ACCOUNT);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

// POST /push/subscribe
// Speichert den FCM-Token des Geräts für den angemeldeten Nutzer.
router.post('/subscribe', requireAuth, (req, res) => {
  const { fcm_token } = req.body ?? {};
  if (!fcm_token) {
    return res.status(400).json({ error: 'fcm_token fehlt' });
  }

  db.prepare(`
    INSERT INTO push_tokens (user_id, fcm_token)
    VALUES (?, ?)
    ON CONFLICT(fcm_token) DO UPDATE SET user_id = excluded.user_id
  `).run(req.userId, fcm_token);

  res.json({ ok: true });
});

// DELETE /push/subscribe
// Entfernt den FCM-Token beim Abmelden.
router.delete('/subscribe', requireAuth, (req, res) => {
  const { fcm_token } = req.body ?? {};
  if (fcm_token) {
    db.prepare('DELETE FROM push_tokens WHERE fcm_token = ? AND user_id = ?')
      .run(fcm_token, req.userId);
  }
  res.json({ ok: true });
});

// POST /push/send  (intern – z.B. von einem Cron-Job aufrufbar)
// Sendet eine Push-Benachrichtigung an alle Tokens eines Nutzers.
// Body: { user_id, title, body }
router.post('/send', (req, res) => {
  // Einfacher API-Key-Schutz für interne Aufrufe
  const key = req.headers['x-internal-key'];
  if (key !== process.env.INTERNAL_KEY && process.env.INTERNAL_KEY) {
    return res.status(403).json({ error: 'Nicht autorisiert' });
  }

  const { user_id, title, body } = req.body ?? {};
  if (!user_id || !title || !body) {
    return res.status(400).json({ error: 'user_id, title und body erforderlich' });
  }

  const tokens = db
    .prepare('SELECT fcm_token FROM push_tokens WHERE user_id = ?')
    .all(user_id)
    .map((r) => r.fcm_token);

  if (tokens.length === 0) {
    return res.json({ sent: 0 });
  }

  // Multicast an alle Geräte des Nutzers
  admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    android: { priority: 'high' },
  }).then((result) => {
    // Abgelaufene Tokens entfernen
    result.responses.forEach((r, i) => {
      if (!r.success &&
          (r.error?.code === 'messaging/registration-token-not-registered' ||
           r.error?.code === 'messaging/invalid-registration-token')) {
        db.prepare('DELETE FROM push_tokens WHERE fcm_token = ?').run(tokens[i]);
      }
    });
    res.json({ sent: result.successCount, failed: result.failureCount });
  }).catch((err) => {
    console.error('FCM Fehler:', err);
    res.status(500).json({ error: 'Push fehlgeschlagen' });
  });
});

// GET /push/check-stale
// Prüft die übergebene API-URL und sendet eine Push-Benachrichtigung
// wenn die Daten veraltet sind (data_age_s > threshold).
// Gedacht für einen Cron-Job (z.B. alle 30 Minuten).
router.get('/check-stale', async (req, res) => {
  const key = req.headers['x-internal-key'];
  if (key !== process.env.INTERNAL_KEY && process.env.INTERNAL_KEY) {
    return res.status(403).json({ error: 'Nicht autorisiert' });
  }

  const { api_url, user_id, threshold_s = 3600 } = req.query;
  if (!api_url || !user_id) {
    return res.status(400).json({ error: 'api_url und user_id erforderlich' });
  }

  try {
    const response = await fetch(api_url);
    const data = await response.json();
    const age = parseInt(data.data_age_s ?? 0, 10);

    if (age > parseInt(threshold_s, 10)) {
      // Interne Send-Route aufrufen
      const tokens = db
        .prepare('SELECT fcm_token FROM push_tokens WHERE user_id = ?')
        .all(user_id)
        .map((r) => r.fcm_token);

      if (tokens.length > 0) {
        await admin.messaging().sendEachForMulticast({
          tokens,
          notification: {
            title: '⚠️ Wetterstation offline?',
            body: `Keine neuen Daten seit ${Math.round(age / 60)} Minuten.`,
          },
        });
      }
      return res.json({ stale: true, age_s: age });
    }
    res.json({ stale: false, age_s: age });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
