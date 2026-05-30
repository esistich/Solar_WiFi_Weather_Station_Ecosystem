<?php
/**
 * v1/auth/invite_list.php – Einladungscodes auflisten
 *
 * GET /v1/invite/list
 * Header: Authorization: Bearer <jwt>
 */

declare(strict_types=1);

requireJwt();
$db   = getDb();
$rows = $db->query('SELECT code, created_at, used_at FROM invite_codes ORDER BY created_at DESC')->fetchAll();

sendJson(200, ['invites' => $rows]);
