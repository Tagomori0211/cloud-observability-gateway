CREATE TABLE users (
  id          BIGINT       NOT NULL AUTO_INCREMENT,
  misskey_id  VARCHAR(64)  NOT NULL,
  misskey_host VARCHAR(255) NOT NULL DEFAULT 'sushi.ski',
  username    VARCHAR(128) NOT NULL,
  created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_misskey (misskey_host, misskey_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE linked_mc_accounts (
  id          BIGINT       NOT NULL AUTO_INCREMENT,
  user_id     BIGINT       NOT NULL,
  edition     ENUM('java','bedrock') NOT NULL,
  ign         VARCHAR(64)  NOT NULL,
  external_id VARCHAR(64)  NULL,            -- 将来の UUID/XUID 用（ADR-006 ロードマップ）
  linked_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_link_edition_ign (edition, ign),
  KEY idx_link_user (user_id),
  CONSTRAINT fk_link_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE sessions (
  id          BIGINT       NOT NULL AUTO_INCREMENT,
  token_hash  CHAR(64)     NOT NULL,        -- sha256(cookie値) の hex
  user_id     BIGINT       NOT NULL,
  expires_at  TIMESTAMP    NOT NULL,
  created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_sessions_token (token_hash),
  KEY idx_sessions_user (user_id),
  CONSTRAINT fk_sessions_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE link_audit (
  id        BIGINT      NOT NULL AUTO_INCREMENT,
  user_id   BIGINT      NULL,
  action    ENUM('link','unlink') NOT NULL,
  edition   ENUM('java','bedrock') NOT NULL,
  ign       VARCHAR(64) NOT NULL,
  actor     VARCHAR(128) NOT NULL,          -- 'self' 等
  at        TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_audit_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
