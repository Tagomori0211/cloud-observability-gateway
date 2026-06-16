ALTER TABLE users
  ADD COLUMN password_hash VARCHAR(255) NULL AFTER username,
  ADD UNIQUE KEY uq_users_username (username);
