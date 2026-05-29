# SWS Backend – Einrichtung

## Voraussetzungen
- Node.js 20+
- Firebase-Projekt (kostenlos auf console.firebase.google.com)

## Setup

```bash
cd backend
npm install
cp .env.example .env
# .env ausfüllen (JWT_SECRET, FIREBASE_SERVICE_ACCOUNT-Pfad)
npm start
```

## Firebase Service Account
1. Firebase Console → Projekteinstellungen → Service Accounts
2. "Neuen privaten Schlüssel generieren" → JSON herunterladen
3. Als `firebase-service-account.json` in den `backend/`-Ordner legen
4. In `.env`: `FIREBASE_SERVICE_ACCOUNT=./firebase-service-account.json`

## Endpunkte

| Methode | Pfad | Auth | Beschreibung |
|---------|------|------|--------------|
| POST | /auth/register | – | Neuen Nutzer registrieren |
| POST | /auth/login | – | Login → JWT |
| GET | /auth/me | JWT | Nutzerinfo |
| POST | /push/subscribe | JWT | FCM-Token speichern |
| DELETE | /push/subscribe | JWT | FCM-Token entfernen |
| POST | /push/send | x-internal-key | Push senden (intern) |
| GET | /push/check-stale | x-internal-key | Daten-Alter prüfen + Push |

## Cron-Job (optional)
Um veraltete Stationsdaten zu melden, z.B. alle 30 Minuten:

```cron
*/30 * * * * curl -s -H "x-internal-key: DEIN_KEY" \
  "http://localhost:3001/push/check-stale?api_url=https://meinserver.de/api/data.php&user_id=UUID"
```
