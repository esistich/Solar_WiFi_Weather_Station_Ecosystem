const express = require('express');
const bcrypt  = require('bcryptjs');
const jwt     = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const db = require('../db');

const router = express.Router();
const TOKEN_TTL = '30d';

// POST /auth/register
router.post('/register', async (req, res) => {
  const { email, password } = req.body ?? {};
  if (!email || !password) {
    return res.status(400).json({ error: 'E-Mail und Passwort erforderlich' });
  }

  const exists = db.prepare('SELECT id FROM users WHERE email = ?').get(email);
  if (exists) {
    return res.status(409).json({ error: 'E-Mail bereits registriert' });
  }

  const hash = await bcrypt.hash(password, 12);
  const id   = uuidv4();
  db.prepare('INSERT INTO users (id, email, password) VALUES (?, ?, ?)').run(id, email, hash);

  const token = jwt.sign({ sub: id }, process.env.JWT_SECRET, { expiresIn: TOKEN_TTL });
  res.status(201).json({ id, email, token });
});

// POST /auth/login
router.post('/login', async (req, res) => {
  const { email, password } = req.body ?? {};
  if (!email || !password) {
    return res.status(400).json({ error: 'E-Mail und Passwort erforderlich' });
  }

  const user = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
  if (!user) {
    return res.status(401).json({ error: 'Ungültige Anmeldedaten' });
  }

  const ok = await bcrypt.compare(password, user.password);
  if (!ok) {
    return res.status(401).json({ error: 'Ungültige Anmeldedaten' });
  }

  const token = jwt.sign({ sub: user.id }, process.env.JWT_SECRET, { expiresIn: TOKEN_TTL });
  res.json({ id: user.id, email: user.email, token });
});

// GET /auth/me  (Token prüfen)
router.get('/me', require('../middleware/jwt').requireAuth, (req, res) => {
  const user = db.prepare('SELECT id, email FROM users WHERE id = ?').get(req.userId);
  if (!user) return res.status(404).json({ error: 'Benutzer nicht gefunden' });
  res.json(user);
});

module.exports = router;
