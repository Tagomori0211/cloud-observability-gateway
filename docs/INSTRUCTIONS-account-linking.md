# 作業指示書: Misskey(MiAuth) 連携 + マイページ機能

> **対象**: Claude Code (Sonnet)
> **最終更新**: 2026-06-16 (JST)
> **リポジトリ**: フロント (Flutter Web) + バックエンド (Kotlin / Ktor) のモノレポ
> **意思決定の根拠**: 別ファイル `ADR-account-linking.md`（ADR-001〜009）を**唯一の決定根拠**とする。本書と矛盾したら ADR を優先し、人間に確認すること。
> **ゴール**: Misskey(MiAuth) でログインし、自前アカウントを発行。マイページで Java / Bedrock のゲーム内ユーザー名(IGN)を紐付けて表示する。

---

## 0. このドキュメントの読み方（最重要・先に読む）

このタスクは **3層の防護柵**で守られている。Sonnet は以下を厳守すること。

| 層 | 何で守るか | 強制力 |
|---|---|---|
| **層① スコープ柵** | 本書 §2 の「やること / 触るなリスト」 | 規範（必ず従う） |
| **層② CLAUDE.md** | §6 の横断ルール（毎セッション読込） | 規範 |
| **層③ フック** | §7 の `.claude/settings.json` + スクリプト | **確定遵守**（PreToolUse exit 2 で物理ブロック） |

**ドリフト（仕様逸脱）防止の鉄則:**

1. **本書に書かれていないファイルは触らない。** 「ついで」のリファクタ・改名・最適化を禁止する。
2. **1コミット=1論点。** タスク(§5)の単位でコミットし、無関係な変更を混ぜない。
3. **判断に迷ったら止まって人間に聞く。** 勝手に代替案へ流れない。ADR で決まっていない設計選択が出たら、実装せずに質問する。
4. **既存の稼働経路（gRPCメトリクス）には一切触れない。** 新機能は REST の別経路で足す（ADR-007）。
5. **秘密情報をコード・ログ・レスポンス・コミットに出さない**（ADR-002）。

---

## 1. 正規名称テーブル（ドリフト増幅の防止）

リポジトリ内に `tagomori-*` と `sushiski-*` の混在がある。**正規は `tagomori-*`**（稼働中の Terraform / docker-compose / README / pubspec が一致）。以下を唯一の正とし、勝手に改名しないこと。

| 種別 | 正規名 |
|---|---|
| GCE VM | `tagomori-app` |
| 公開ドメイン | `app.tagomori.dev` |
| Flutter パッケージ名 | `tagomori_status_frontend` |
| 既存 Secret | `tagomori-tunnel-token` |
| **新規 DB 名** | `tagomori_status` |
| **新規 DB ユーザー** | `app` |
| compose サービス（新規DB） | `mariadb` |

> 注: `infra/ansible/inventory.ini` の `sushiski-app` は既存ドリフト（Terraform の `tagomori-app` と不一致）。**本タスクでは触らない。複製・踏襲もしない。** sushiski-* への全体改名は別タスク。

---

## 2. スコープ（層①）

### 2-1. やること（in scope）

- **DB**: APP-instance の既存 `deploy/docker-compose.yml` に MariaDB を1サービス追加（ADR-003）。
- **スキーマ**: Flyway マイグレーション（`users` / `linked_mc_accounts` / `sessions` / `link_audit`）（ADR-008）。
- **バックエンド**: 既存 Ktor に **REST ルート `/api/*`** を追加（認証・マイページ・連携）（ADR-007/009）。
- **フロント**: MiAuth 完了処理をバックエンド呼び出しへ移行し、マイページ画面を追加（ADR-009）。
- **設定テンプレ**: `.env.example` に新 DB キーを追記。

### 2-2. 触るなリスト（DO NOT TOUCH — 変更・削除・改名すべて禁止）

| 対象 | 理由 |
|---|---|
| `shared.proto` | gRPC SSOT（メトリクス経路）。不変（ADR-007） |
| `backend/src/main/kotlin/app/SharedServiceImpl.kt` | 既存 gRPC 実装。不変 |
| `frontend/lib/services/metrics_grpc_service.dart` | 既存 gRPC クライアント。不変 |
| `deploy/envoy.yaml` | 既存ルーティング。`/api` は**既存 `/` 経路に相乗り**するため変更不要 |
| `cloudflared` 関連（compose の該当サービス・Tunnel 設定） | 壊すと公開が落ちる |
| `infra/**`（terraform / cloud-init / ansible） | 本タスクのスコープ外。DB 資格情報は §5-T6 の手動手順で対応 |
| `.env` / `deploy/.env` | 秘密。読まない・書かない・コミットしない（`.env.example` は可） |
| `frontend/lib/src/generated/**` | CI 生成物 |

### 2-3. 禁止コマンド / 禁止パターン

- `docker-compose`（v1）→ **必ず `docker compose`（v2）**。
- `flutter build web` に `--web-renderer` を付けない（Flutter 3.29 で削除済み）。
- `git push` 全般禁止（**デプロイは main への push を人間が行い CI 経由**）。
- `terraform apply/destroy`、`gcloud secrets ...`、`DROP DATABASE/TABLE`、`rm -rf /`・`rm -rf ~`・`.env`/`.git` への削除、`chmod 777`、`curl ... | bash` を禁止。
- Envoy の gRPC ルートの `timeout: 0s` を消さない。compose に `networks: internal: true` を足さない。

### 2-4. 進め方（順序固定）

**T1 build.gradle → T2 DB/Flyway → T3 バックエンドREST → T4 compose → T5 フロント → T6 設定/手順** の順。各 T 完了ごとに **ビルドが通ること**を確認し、コミット。

---

## 3. 全体アーキテクチャ（新機能の位置づけ）

```
ブラウザ (Flutter Web, app.tagomori.dev)
  │  ① ログイン: /miauth/<session> へリダイレクト（フロントが組立）
  │  ④ <session> を Backend へ POST、以降は Cookie(sid) で認証
  ▼
Cloudflare Edge ══ Tunnel ══► cloudflared ──► Envoy :80
                                                 ├─ "/shared."  → Ktor :50051 (gRPC: 既存・不変)
                                                 └─ "/"・"/api/" → Ktor :8080
                                                                      ├─ 静的配信 (Flutter SPA: 既存)
                                                                      └─ REST /api/* (新規)
                                                                            │
        ┌───────────────────────────────────────────────────────────────┘
        ▼ JDBC (compose ネットワーク内部)
   MariaDB :3306 (新規・同一 compose、ホスト非公開)
        │
        └─ users / linked_mc_accounts / sessions / link_audit

   ② MiAuth /api/miauth/<session>/check は Backend が実行（host は sushi.ski 固定）
   ③ 検証 OK → users upsert → sessions 作成 → Set-Cookie(sid) → Misskey トークン破棄
```

**MiAuth フロー（再掲）**: フロントが `session` UUID を生成しリダイレクト → 承認後 callback → フロントは `session` を Backend に渡すだけ → Backend が `/check` 実行・Cookie 発行。

---

## 4. 成果物ファイル一覧

```
backend/
  build.gradle.kts                      # 【改修】依存追加（mariadb-jdbc / HikariCP / Flyway / server content-negotiation）
  src/main/kotlin/app/
    Main.kt                             # 【改修】DB初期化呼出 + ContentNegotiation + REST ルート登録（gRPC部は触らない）
    db/Database.kt                      # 【新規】HikariCP プール + Flyway migrate
    db/Db.kt                            # 【新規】withConnection ヘルパ（try-with-resources）
    repo/UserRepository.kt              # 【新規】users upsert / find（prepared statement のみ）
    repo/SessionRepository.kt           # 【新規】session 作成/検索(token_hash)/削除
    repo/LinkRepository.kt              # 【新規】linked_mc_accounts CRUD + link_audit
    auth/MiAuthClient.kt                # 【新規】sushi.ski /api/miauth/<session>/check（host固定）
    auth/SessionAuth.kt                 # 【新規】Cookie 読取・検証 interceptor / set / clear
    routes/AuthRoutes.kt                # 【新規】/api/auth/*  ・ /api/logout
    routes/MeRoutes.kt                  # 【新規】/api/me ・ /api/me/accounts
  src/main/resources/db/migration/
    V1__init.sql                        # 【新規】スキーマ（SSOT）

frontend/
  lib/services/misskey_auth_service.dart  # 【改修】checkSession を Backend /api/auth/miauth/complete 呼出へ
  lib/services/account_service.dart       # 【新規】/api/me ・ /api/me/accounts ・ /api/logout（Cookie送信）
  lib/models/user_profile.dart            # 【新規】
  lib/models/linked_account.dart          # 【新規】
  lib/screens/mypage_screen.dart          # 【新規】ログイン後の遷移先。連携の表示/追加/削除
  lib/screens/login_screen.dart           # 【改修】認証後に MyPage へ遷移
  lib/screens/status_screen.dart          # 【触るな】メトリクスは現状維持（MyPage からリンクするだけ）

deploy/
  docker-compose.yml                    # 【改修】mariadb サービス + volume + api への DB env / depends_on

.env.example                            # 【改修】DB_URL / DB_USER / DB_PASSWORD / MARIADB_* を追記

.claude/                                # 【新規・人間が配置】§7。Sonnet は自分では編集しない
  settings.json
  hooks/guard-paths.sh
  hooks/guard-bash.sh
  hooks/post-format.sh
```

---

## 5. タスク詳細

### T1. backend/build.gradle.kts（依存追加のみ）

既存の version 定義・gRPC 設定・shadowJar 設定は**変更しない**。以下を `dependencies` に追加（バージョンは下記を既知良好の起点として**固定**し、`+` で浮かせない）。

```kotlin
// --- 追加（DB / REST 用）---
implementation("io.ktor:ktor-server-content-negotiation:$ktorVersion")  // サーバ側JSON
implementation("org.mariadb.jdbc:mariadb-java-client:3.5.2")
implementation("com.zaxxer:HikariCP:6.2.1")
implementation("org.flywaydb:flyway-core:11.3.0")
implementation("org.flywaydb:flyway-mysql:11.3.0")
```

> `kotlinx-serialization-json` と `ktor-serialization-kotlinx-json` は既存（クライアント用）にあるため流用。Kotlin 2.0.21 / JDK 21 を維持。

### T2. スキーマ（Flyway）— `V1__init.sql`

これが**スキーマの唯一の正**。手書き DDL を他所に散らさない。

```sql
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
```

`db/Database.kt`: HikariCP で `DB_URL`/`DB_USER`/`DB_PASSWORD`(env) からプール生成 → 起動時に `Flyway.configure().dataSource(...).load().migrate()`。
**SQL は必ず prepared statement のみ**（文字列連結禁止）。各リポジトリは `connection.use { ... }`（try-with-resources）でリーク防止。

### T3. バックエンド REST（`/api/*`）

#### エンドポイント契約（ADR-010 反映済み — MiAuthは初回登録専用、再ログインはID/PASS）

| メソッド | パス | 認証 | リクエスト | 成功 | 主なエラー |
|---|---|---|---|---|---|
| POST | `/api/auth/miauth/register` | 不要 | `{"session":"<uuid>"}` | 200 `{username, needPassword:true}`（Cookie発行なし） | 400 形式不正 / 401 MiAuth検証失敗 / 409 `already_registered` |
| POST | `/api/auth/register/set-password` | 不要 | `{"username":"<id>","password":"<8文字以上>"}` | 200 `{user}` + `Set-Cookie: sid=…` | 400 短すぎ / 404 ユーザー無し / 409 設定済み |
| POST | `/api/auth/login` | 不要 | `{"username":"<id>","password":"<pass>"}` | 200 `{user}` + `Set-Cookie: sid=…` | 401 認証情報不正 |
| GET | `/api/me` | 要 | — | 200 `{user, accounts:[…]}` | 401 |
| POST | `/api/logout` | 要 | — | 204（Cookie 失効 + session 行削除） | 401 |
| POST | `/api/me/accounts` | 要 | `{"edition":"java"\|"bedrock","ign":"<name>"}` | 201 `{account}` | 400 / 409 重複 |
| DELETE | `/api/me/accounts/{id}` | 要 | — | 204（本人所有のみ） | 401 / 404 |

#### 実装要点

- **MiAuthClient**: `POST https://sushi.ski/api/miauth/{session}/check` のみ叩く。フロントから来る `host` は**一切信用せず**、`sushi.ski` をコード/設定で固定（ADR-009）。レスポンス `ok==true` のときだけ `user.id` / `user.username` を採用。**`token` は使い終わりにメモリから捨て、保存しない**（ADR-002）。
- **セッション**: 発行時に `SecureRandom` で 32 byte 乱数 → base64url を Cookie 値 `sid` に。DB には `sha256(値)` を `sessions.token_hash` に保存。
  Cookie 属性: `HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=2592000`(30日)。
- **SessionAuth interceptor**: 保護ルートで `sid` Cookie → sha256 → `sessions` 照合 → 期限切れ/不在は 401。ヒットしたら `user` を call 属性に載せる。
- **入力バリデーション**: `edition` は enum 2値のみ。`ign` は `^[A-Za-z0-9_]{1,16}$`（Java想定）/ Bedrock は空白許容のため別途 `^[\w ]{1,32}$` 程度。重複は UNIQUE 制約 + 409 で弾く。
- **Main.kt**: 既存 `embeddedServer(Netty, 8080)` ブロック内に `install(ContentNegotiation){ json() }` と `route("/api"){ … }` を追加。**gRPC サーバー（:50051）の起動コードには触れない。**

> **⚠ SPA フォールバック衝突（最重要 gotcha）**: 既存 `singlePageApplication` は貪欲で `/api/*` を index.html に飲み込む恐れ。**REST ルート（`route("/api"){…}`）を `singlePageApplication{…}` より前に登録**し、`/api` 配下が SPA フォールバックに落ちないことを必ず確認する。

### T4. deploy/docker-compose.yml（MariaDB 追加）

`api` サービスへ DB env と `depends_on` を追加し、`mariadb` サービス + 名前付きボリュームを新設。**ホストポートは公開しない。`networks: internal: true` は付けない。**

```yaml
services:
  # （cloudflared / envoy / api は既存。api にだけ下記を追記）
  api:
    # ...既存設定...
    environment:
      VICTORIA_METRICS_URL: ${VICTORIA_METRICS_URL}   # 既存
      DB_URL: ${DB_URL}
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
    depends_on:
      - mariadb            # 既存の depends_on があればマージ

  mariadb:
    image: mariadb:11.4
    container_name: app-mariadb
    environment:
      MARIADB_DATABASE: ${MARIADB_DATABASE}
      MARIADB_USER: ${MARIADB_USER}
      MARIADB_PASSWORD: ${MARIADB_PASSWORD}
      MARIADB_ROOT_PASSWORD: ${MARIADB_ROOT_PASSWORD}
    volumes:
      - mariadb-data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    # ports は定義しない（compose ネットワーク内のみ）

volumes:
  mariadb-data:
```

### T5. フロントエンド

- **misskey_auth_service.dart（改修）**: `startAuth` は現状維持（リダイレクト URL 組立）。`checkSession(host, session)` を廃し、`completeLogin(session)` に置換 → `POST /api/auth/miauth/complete` を叩く。**Misskey トークンのクライアント保持を全廃**（ADR-002）。
- **account_service.dart（新規）**: `/api/me`(GET) / `/api/me/accounts`(POST,DELETE) / `/api/logout`(POST)。**Cookie を必ず送る**。
  > 同一オリジンのため Cookie は自動付与されるが、防御的に `BrowserClient()..withCredentials = true` を用いる。
- **mypage_screen.dart（新規）**: 認証後の遷移先。Misskey ユーザー名 + Java/Bedrock の連携一覧を表示し、追加フォーム（edition 選択 + IGN 入力）と削除ボタンを置く。メトリクス画面 (`StatusScreen`) へのリンクを1つ用意。
- **login_screen.dart（改修）**: 認証成功後の遷移先を `StatusScreen` から `MyPageScreen` に変更（既存のアニメーション/遷移は流用可）。
- **models**: `UserProfile`(misskeyId, username) / `LinkedAccount`(id, edition, ign)。

### T6. 設定・秘密（手動手順の文書化 / infra は触らない）

`.env.example` に追記（**値は書かない**）:

```
# --- Account linking DB (新規) ---
DB_URL=jdbc:mariadb://mariadb:3306/tagomori_status
DB_USER=app
DB_PASSWORD=__set_in_real_env__
MARIADB_DATABASE=tagomori_status
MARIADB_USER=app
MARIADB_PASSWORD=__set_in_real_env__
MARIADB_ROOT_PASSWORD=__set_in_real_env__
```

実際の `~/app/.env` への登録は **人間が手動で実施**（TUNNEL_TOKEN と同方式）。Sonnet は手順を README/コメントに記すのみで、`.env` 自体・`infra/**` には触れない。

---

## 6. CLAUDE.md 追記（層②）

プロジェクトルート `CLAUDE.md` に以下ブロックを追記（既存があればマージ。150行以内を維持）。

```markdown
## このリポジトリの不変条件（必ず守る）

### 正規名称（勝手に改名しない）
- VM=tagomori-app / ドメイン=app.tagomori.dev / Flutterパッケージ=tagomori_status_frontend
- 新規DB名=tagomori_status / DBユーザー=app / composeサービス=mariadb
- ansible の sushiski-app は既存ドリフト。触らない・複製しない。

### アーキテクチャの分界（ADR-007）
- メトリクス = gRPC（:50051, /shared.*）。**既存・不変。触らない。**
- 認証・連携 = REST（/api/*, :8080）。新機能はこちらにのみ足す。
- /api は Envoy の既存 / 経路に相乗り。envoy.yaml は変更しない。

### セキュリティ（ADR-002 / 009）
- Misskey トークンを永続化しない。保存するのは misskey_id / host / username のみ。
- MiAuth の host は sushi.ski に固定。callback の host を信用しない。
- 秘密情報をコード・ログ・レスポンス・コミットに出さない。.env は読まない・書かない。
- DB アクセスは repository 層経由のみ。SQL は prepared statement のみ（文字列連結禁止）。

### 触るな
- shared.proto / SharedServiceImpl.kt / metrics_grpc_service.dart / envoy.yaml
- cloudflared 関連 / infra/** / frontend/lib/src/generated/**

### コマンド規約
- ビルド(backend): `cd backend && ./gradlew --no-daemon shadowJar`
- ビルド(frontend): `cd frontend && flutter pub get && flutter build web --release`（--web-renderer 禁止）
- 起動/再構築: `docker compose up -d --build`（docker-compose v1 禁止）
- envoy 検証: `docker run --rm -v $(pwd)/deploy/envoy.yaml:/envoy.yaml envoyproxy/envoy:v1.31.5 --mode validate -c /envoy.yaml`
- git push 禁止（デプロイは人間が main へ push して CI 実行）。

### 進め方
- 本書に無いファイルは触らない。1コミット=1論点。迷ったら止まって人間に聞く。
```

---

## 7. フック（層③）`.claude/settings.json`

> **配置は人間が行う。** パスは実チェックアウト先に合わせて置換（下記は `settings.json` の `additionalDirectories` に合わせた例）。スクリプトは `chmod +x` し、`jq` が必要。

### `.claude/settings.json`

```json
{
  "permissions": {
    "deny": [
      "Read(./.env)",
      "Read(./deploy/.env)",
      "Edit(./.env)",
      "Edit(./deploy/.env)",
      "Edit(./shared.proto)",
      "Edit(./deploy/envoy.yaml)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "/home/shinari/tagomori-status-frontend/.claude/hooks/guard-paths.sh" }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "/home/shinari/tagomori-status-frontend/.claude/hooks/guard-bash.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "/home/shinari/tagomori-status-frontend/.claude/hooks/post-format.sh" }
        ]
      }
    ]
  }
}
```

> 既存の `permissions.allow` / `additionalDirectories` がある場合はマージ。古い一時用 `allow`（rm -rf 系）は不要なら整理推奨。

### `.claude/hooks/guard-paths.sh`（保護ファイルへの編集を物理ブロック）

```bash
#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit): 触るなリストへの編集を exit 2 でブロック
set -euo pipefail
input="$(cat)"
path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')"
[ -z "$path" ] && exit 0

deny_globs=(
  ".env" "*/.env" "*/deploy/.env"
  "*.tfstate" "*.tfstate.*"
  "*/infra/*"
  "*/shared.proto"
  "*SharedServiceImpl.kt"
  "*metrics_grpc_service.dart"
  "*/deploy/envoy.yaml"
  "*/.git/*"
  "*/.claude/*"
)
for g in "${deny_globs[@]}"; do
  # shellcheck disable=SC2254
  case "$path" in
    $g)
      echo "BLOCKED: '$path' は保護対象（作業指示書 §2-2 のスコープ外）。変更が必要なら人間に相談すること。" >&2
      exit 2 ;;
  esac
done
exit 0
```

### `.claude/hooks/guard-bash.sh`（破壊的/スコープ外コマンドを物理ブロック + commit前 secret-scan）

```bash
#!/usr/bin/env bash
# PreToolUse(Bash): 危険コマンドを exit 2 でブロック
set -euo pipefail
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0
block() { echo "BLOCKED: $1" >&2; exit 2; }

echo "$cmd" | grep -Eiq 'docker-compose([[:space:]]|$)'                 && block "docker-compose(v1) 禁止。docker compose(v2) を使う"
echo "$cmd" | grep -Eiq 'git[[:space:]]+push'                          && block "git push 禁止。デプロイは人間が main へ push し CI 経由"
echo "$cmd" | grep -Eiq 'terraform[[:space:]]+(apply|destroy)'         && block "terraform apply/destroy 禁止（infra はスコープ外）"
echo "$cmd" | grep -Eiq 'gcloud[[:space:]]+secrets'                    && block "Secret Manager 操作は人間が行う"
echo "$cmd" | grep -Eiq 'DROP[[:space:]]+(DATABASE|TABLE)'             && block "DROP 禁止（破壊的）"
echo "$cmd" | grep -Eiq 'chmod[[:space:]]+-?[Rr]?[[:space:]]*777'      && block "chmod 777 禁止"
echo "$cmd" | grep -Eiq 'curl.*\|[[:space:]]*(bash|sh)'                && block "curl | bash 禁止"
echo "$cmd" | grep -Eiq 'rm[[:space:]]+-[a-z]*[rf][a-z]*[[:space:]]+(/|~|\.|\*|\$HOME)([[:space:]]|/|$)' && block "危険な rm -rf 禁止"
echo "$cmd" | grep -Eiq 'rm[[:space:]].*(\.env|\.git)([[:space:]]|/|$)' && block ".env / .git の削除禁止"
echo "$cmd" | grep -Eiq '>[[:space:]]*\.env([[:space:]]|$)'            && block ".env への書き込み禁止"

# git commit 時はステージ済み差分を秘密スキャン
if echo "$cmd" | grep -Eq 'git[[:space:]]+commit'; then
  staged="$(git diff --cached -U0 2>/dev/null || true)"
  if printf '%s' "$staged" | grep -Eiq '(TUNNEL_TOKEN|PASSWORD=|SECRET|PRIVATE KEY|eyJ[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{30,})'; then
    block "ステージ済み差分に秘密情報の疑い。除去してから commit すること"
  fi
fi
exit 0
```

### `.claude/hooks/post-format.sh`（編集後の自動整形・best-effort）

```bash
#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit): 整形。失敗しても常に exit 0
set -euo pipefail
input="$(cat)"
path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')"
[ -z "$path" ] && exit 0
case "$path" in
  *.kt)   command -v ktlint >/dev/null 2>&1 && ktlint -F "$path" >/dev/null 2>&1 || true ;;
  *.dart) command -v dart   >/dev/null 2>&1 && dart format "$path" >/dev/null 2>&1 || true ;;
esac
exit 0
```

> **要点**: セキュリティ系フックは必ず **exit 2**（exit 1 は警告のみでブロックしない）。PreToolUse はパーミッション確認の前に走り、exit 2 でツール呼び出しを完全に止める。

---

## 8. 実装時の注意事項（gotcha 集）

1. **SPA フォールバック衝突**（§5-T3 再掲）: `/api` ルートを `singlePageApplication` より**前**に登録。
2. **MiAuth host 固定**: callback の `?host=` を信用せず `sushi.ski` をサーバ側で固定。
3. **Misskey トークン破棄**: `/check` の `token` は変数に受けたら即捨てる。ログ出力厳禁。
4. **セッションは hash 保存**: Cookie に乱数、DB には sha256。生トークンを DB に入れない。
5. **Cookie 属性**: `HttpOnly; Secure; SameSite=Lax`。CF Tunnel/Envoy はヘッダを素通しするので追加設定不要。
6. **prepared statement のみ**: IGN・session 等すべて placeholder。文字列連結で SQL を組まない。
7. **`docker compose`（v2）**・`--web-renderer` 不使用・`timeout: 0s` 維持・`internal: true` 不追加。
8. **gRPC 経路は不可侵**: `Main.kt` の :50051 起動部、`shared.proto`、`SharedServiceImpl.kt` に触れない。

---

## 9. 受け入れ条件（Definition of Done）

- [ ] `cd backend && ./gradlew --no-daemon shadowJar` 成功（新依存解決込み、proto 自動生成は従来どおり）。
- [ ] アプリ起動時に Flyway が `V1` を適用し、4テーブルが作成される。
- [ ] `POST /api/auth/miauth/complete` が `ok:true` 時にユーザーを upsert し、`Set-Cookie: sid=…`（HttpOnly/Secure/SameSite）を返す。`ok:false` で 401。
- [ ] `GET /api/me` が Cookie 認証で `{user, accounts}` を返し、未認証は 401。
- [ ] `POST /api/me/accounts` が edition/ign を検証し連携を追加（重複は 409）、`DELETE …/{id}` が本人所有のみ削除。
- [ ] DB に Misskey トークンが**保存されていない**（schema にカラムが無い）。
- [ ] `flutter build web --release` 成功。ログイン → MyPage 遷移 → 連携の追加/削除/表示が動く。
- [ ] `docker compose up -d --build` で `app-mariadb` が healthy、`api` が DB 接続成功。
- [ ] `shared.proto` / `SharedServiceImpl.kt` / `metrics_grpc_service.dart` / `envoy.yaml` / `infra/**` に**差分が無い**（`git diff --stat` で確認）。
- [ ] `.env` がコミットに含まれない。`.env.example` にのみ新キーが追記されている。
- [ ] フック3本が配置され、保護ファイル編集と危険コマンドが実際にブロックされることを1回試験した。

---

## 10. 動作確認手順（デプロイ後）

```bash
# DB
docker compose ps                         # app-mariadb が healthy
docker compose logs --tail=40 api         # Flyway migrate 成功 / DB 接続ログ

# 認証〜連携（ブラウザ）
# 1. app.tagomori.dev でログイン → Sushi.ski で承認 → MyPage に着地
# 2. DevTools > Application > Cookies に sid（HttpOnly/Secure）が1つ
# 3. Java/Bedrock の IGN を追加 → 再読込しても残る → 削除できる

# API 直叩き（Cookie 必須なのでブラウザ or 取得済み sid で）
curl -I https://app.tagomori.dev/api/me   # 未認証は 401

# メトリクス経路が無傷か（回帰確認）
# DevTools > Network で /shared.MetricsService/* が従来どおり 200
```

---

## 11. 参照

- 意思決定の根拠: `ADR-account-linking.md`（ADR-001〜009）
- MiAuth: フロント既存実装 `frontend/lib/services/misskey_auth_service.dart` が手本。host は `sushi.ski` 固定で再実装。
- 既存全体構成: リポジトリ `README.md` / `Shijisho.md`（v2, gRPC/Tunnel 構築の前作業指示書）。
