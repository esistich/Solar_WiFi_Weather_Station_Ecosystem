<?php
/**
 * auth.php – Gemeinsame HTTP Basic Auth Hilfsdatei
 *
 * Wird von data.php und history.php eingebunden.
 * Credentials hier EINMALIG pflegen – sie gelten für alle Endpunkte.
 *
 * Diese Datei per .htaccess vor Direktzugriff schützen:
 *   <Files "auth.php">
 *       Require all denied
 *   </Files>
 */

define('API_USER', 'YOUR_API_USER');   // muss mit Settings26.h übereinstimmen
define('API_PASS', 'YOUR_API_PASS');   // muss mit Settings26.h übereinstimmen

/**
 * Prüft HTTP Basic Auth. Bricht mit 401 ab wenn nicht autorisiert.
 */
function requireBasicAuth(): void
{
	$user = $_SERVER['PHP_AUTH_USER'] ?? '';
	$pass = $_SERVER['PHP_AUTH_PW']   ?? '';

	if (!hash_equals(API_USER, $user) || !hash_equals(API_PASS, $pass)) {
		header('WWW-Authenticate: Basic realm="Solar Weather Station"');
		http_response_code(401);
		echo json_encode(['error' => 'Nicht autorisiert'], JSON_UNESCAPED_UNICODE);
		exit;
	}
}
