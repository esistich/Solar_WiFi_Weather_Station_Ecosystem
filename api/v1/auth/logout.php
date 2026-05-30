<?php
/**
 * v1/auth/logout.php – App-Logout (clientseitig: Token verwerfen)
 * Serverseitig keine Aktion nötig bei stateless JWT.
 */

declare(strict_types=1);

requireJwt(); // Token muss gültig sein
sendJson(200, ['ok' => true]);
