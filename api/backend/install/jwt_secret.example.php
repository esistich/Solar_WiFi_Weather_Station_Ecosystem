<?php
/**
 * jwt_secret.php – NICHT ins Git committen!
 * Per FTP nach sws/api/ hochladen (eine Ebene über backend/).
 * Diese Datei wird von jwt.php eingebunden wenn keine
 * JWT_SECRET-Umgebungsvariable gesetzt ist.
 *
 * Eigenen Zufallsstring eintragen (mind. 32 Zeichen):
 */
define('JWT_SECRET_VALUE', 'REDACTED_JWT_SECRET');
