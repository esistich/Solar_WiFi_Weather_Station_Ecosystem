require('dotenv').config();
const express = require('express');
const cors    = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

// Routen
app.use('/auth', require('./routes/auth'));
app.use('/push', require('./routes/push'));

// Health-Check
app.get('/health', (_req, res) => res.json({ status: 'ok' }));

const PORT = process.env.PORT ?? 3001;
app.listen(PORT, () => {
  console.log(`SWS Backend läuft auf Port ${PORT}`);
});
