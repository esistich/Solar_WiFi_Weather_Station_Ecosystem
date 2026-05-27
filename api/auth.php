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
 * Setzt CORS-Header damit Home Assistant (und Browser-Dashboards) die API
 * direkt ansprechen können. Bei OPTIONS-Preflight sofort beenden.
 */
function sendCorsHeaders(): void
{
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
    header('Access-Control-Allow-Headers: Authorization, Content-Type');
    if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
        http_response_code(204);
        exit;
    }
}

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
