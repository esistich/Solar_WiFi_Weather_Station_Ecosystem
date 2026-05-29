<?php
/**
 * db.php – PDO-Datenbankverbindung für das Backend.
 * Gleiche Credentials wie swsapi/lib/db.php – eigenständige Kopie
 * damit keine Pfadabhängigkeit zwischen den beiden Deployments besteht.
 */

if (!defined('DB_HOST')) define('DB_HOST',    'localhost');
if (!defined('DB_NAME')) define('DB_NAME',    'cla2lhsne_timm_sander_netsite');
if (!defined('DB_USER')) define('DB_USER',    'cla2lhsne_timm_sander_netsite');
if (!defined('DB_PASS')) define('DB_PASS',    'zayzsNTSdlXbkrlL4Z1d');
if (!defined('DB_CHARSET')) define('DB_CHARSET', 'utf8mb4');

if (!function_exists('getDb')) {
    function getDb(): PDO
    {
        static $pdo = null;
        if ($pdo === null) {
            $dsn = sprintf('mysql:host=%s;dbname=%s;charset=%s', DB_HOST, DB_NAME, DB_CHARSET);
            $pdo = new PDO($dsn, DB_USER, DB_PASS, [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES   => false,
            ]);
        }
        return $pdo;
    }
}
