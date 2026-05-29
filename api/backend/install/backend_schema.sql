-- backend_schema.sql
-- Neue Tabellen für das PHP-Backend (Auth + Push)
-- In phpMyAdmin oder per CLI ausführen.
-- Die measurements-Tabelle der bestehenden API bleibt unverändert.

CREATE TABLE IF NOT EXISTS users (
	id         INT AUTO_INCREMENT PRIMARY KEY,
	email      VARCHAR(255) NOT NULL UNIQUE,
	password   VARCHAR(255) NOT NULL,
	created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS push_tokens (
	id         INT AUTO_INCREMENT PRIMARY KEY,
	user_id    INT          NOT NULL,
	fcm_token  VARCHAR(512) NOT NULL,
	created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
	UNIQUE KEY uq_token (fcm_token),
	CONSTRAINT fk_pt_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
