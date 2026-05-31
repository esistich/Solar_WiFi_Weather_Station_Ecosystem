<?php
/**
 * credentials.example.php – Vorlage für api/config/credentials.php
 *
 * SETUP:
 *   cp credentials.example.php credentials.php
 *   Dann credentials.php mit eigenen Werten befüllen.
 *
 * credentials.php ist in .gitignore – NIEMALS committen!
 */

// HTTP Basic Auth – muss mit Settings26.h der Station übereinstimmen
define('API_USER', 'change_me_user');
define('API_PASS', 'change_me_password');

// JWT für Flutter-App (mind. 32 zufällige Zeichen; z.B. via: openssl rand -hex 32)
define('JWT_SECRET_VALUE', 'change_me_jwt_secret_min_32_chars');
define('JWT_TTL',          30 * 24 * 3600); // 30 Tage

// Admin-Dashboard Login
define('ADMIN_USER',      'admin');
define('ADMIN_PASS_HASH', password_hash('change_me_admin_password', PASSWORD_BCRYPT));
