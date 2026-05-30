<?php
/**
 * v1/auth/invite_create.php – Einladungscode erstellen
 *
 * POST /v1/invite/create
 * Header: Authorization: Bearer <jwt>
 */

declare(strict_types=1);

requireJwt();
$db   = getDb();
$code = strtoupper(bin2hex(random_bytes(5))); // 10-stelliger Hex-Code

$db->prepare('INSERT INTO invite_codes (code, created_by) VALUES (?, ?)')
   ->execute([$code, 0]);

sendJson(200, ['code' => $code]);
