const jwt = require('jsonwebtoken');

/**
 * Express-Middleware: prüft den Authorization-Header auf ein gültiges JWT.
 * Setzt req.userId bei Erfolg.
 */
function requireAuth(req, res, next) {
  const header = req.headers['authorization'];
  if (!header?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Kein Token' });
  }

  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    req.userId = payload.sub;
    next();
  } catch {
    res.status(401).json({ error: 'Token ungültig oder abgelaufen' });
  }
}

module.exports = { requireAuth };
