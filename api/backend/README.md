# PHP-Backend für SWS-App

Ersetzt das ursprüngliche Node.js-Backend.  
Läuft direkt auf one.com Shared Hosting (PHP 8 + MySQL).

## Dateien

| Datei | Zweck |
|---|---|
| `index.php` | Zentraler Router (`?route=auth|push&action=…`) |
| `auth.php` | Registrierung, Login (JWT HS256) |
| `push.php` | FCM-Token-Verwaltung und Push-Versand |
| `jwt.php` | Schlanke HS256-Implementierung (kein Composer) |
| `db.php` | Leitet zur gemeinsamen `api/lib/db.php` weiter |
| `install/backend_schema.sql` | MySQL-Tabellen `users` + `push_tokens` |
| `.htaccess` | Rewrite auf `index.php`, schützt Hilfsdateien |

## Deployment auf one.com

1. Alle Dateien nach `sws/api/backend/` hochladen (FTP).
2. `install/backend_schema.sql` in phpMyAdmin ausführen.
3. In `jwt.php` den Platzhalter `ersetze_mit_langem_zufaelligen_string`  
   durch einen echten Zufallsstring ersetzen (z. B. 64 Hex-Zeichen).
4. **Firebase Service-Account einrichten:**
   - [console.firebase.google.com](https://console.firebase.google.com) → Projekt anlegen
   - Android-App registrieren, `google-services.json` nach `app/android/app/` kopieren
   - **Projekteinstellungen → Service-Konten → Neuen privaten Schlüssel generieren**
   - Heruntergeladene JSON-Datei (`swsfb-11c77-firebase-adminsdk-fbsvc-7dc4d2384c.json`) nach `sws/api/` hochladen  
     (eine Ebene oberhalb von `backend/`, per `.htaccess` geschützt)
   - `jwt_secret.php` (aus `jwt_secret.example.php` ableiten) → `sws/api/jwt_secret.php` hochladen  
     (direkt neben `backend/`, per `.htaccess` geschützt)

## API-Endpunkte

```
POST /sws/api/backend/index.php?route=auth&action=register
POST /sws/api/backend/index.php?route=auth&action=login
POST /sws/api/backend/index.php?route=auth&action=logout

POST   /sws/api/backend/index.php?route=push&action=register    (Bearer Token)
DELETE /sws/api/backend/index.php?route=push&action=unregister  (Bearer Token)
POST   /sws/api/backend/index.php?route=push&action=send        (Bearer Token)
```

## Sicherheitshinweise

- `jwt.php` und `db.php` sind per `.htaccess` vor Direktzugriff geschützt.
- Das `install/`-Verzeichnis ist komplett gesperrt.
- JWT_SECRET sollte nie im Repository landen – ggf. per `.env`-Datei setzen  
  (one.com unterstützt `putenv`/`getenv`).
