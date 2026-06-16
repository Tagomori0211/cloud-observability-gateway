# ADR集 — sushiski Status Platform: アカウント連携機能

| 項目 | 値 |
|---|---|
| 対象システム | sushiski Status Platform（Flutter Web + Kotlin/Ktor + Envoy + Cloudflare Tunnel） |
| 関連リポジトリ | フロント + backend（モノレポ） |
| 最終更新 | 2026-06-15 (JST) |
| 起票 | 田籠 勇吉 / しなり |
| 実装担当 | Claude Code (Sonnet) ※防護柵は別ファイル「作業指示書」で規定 |
| スコープ | Misskey(MiAuth) でログインし、Java / Bedrock のゲーム内ユーザー名を紐付けて表示するマイページ機能の追加 |

> このファイルは**意思決定の記録のみ**。実装手順・防護柵・タスク分割は別ファイル「作業指示書」に分離する。

---

## 決定ログ（index）

| # | タイトル | ステータス |
|---|---|---|
| ADR-001 | 認証セッション方式 | ✅ Accepted |
| ADR-002 | Misskeyアクセストークンの保管 | ✅ Accepted |
| ADR-003 | MariaDB の配置 | ✅ Accepted |
| ADR-004 | ゲーム内アカウントの連携方式 | ✅ Accepted（v1=純粋自己申告） |
| ADR-005 | ゲーム内コマンドの実装場所 | ⛔ Superseded（ADR-004/006により不要化） |
| ADR-006 | Bedrock 身元の扱い | ✅ Accepted |
| ADR-007 | 新ロジックの設置場所 | ✅ Accepted |
| ADR-008 | スキーマ設計 | ✅ Accepted |
| ADR-009 | アカウントシステムの所有権モデル | ✅ Accepted |

---

## ADR-001 認証セッション方式

- **ステータス**: ✅ Accepted
- **日付**: 2026-06-15
- **コンテキスト**: マイページには認証が必要。現状フロントは MiAuth トークンをクライアント側に持つのみで、バックエンドは認証主体を持たない。アカウント連携という機微操作を扱う。
- **決定**: サーバー側セッション。`HttpOnly` + `Secure` + `SameSite` Cookie に不透明なセッションIDを載せ、実体は MariaDB の `sessions` テーブルで管理する。Cookie には乱数トークン、DBにはそのハッシュ（sha256）を保存し、漏洩時の影響を抑える。
- **検討した代替案**:
  - (A) Misskeyトークンを毎リクエスト Backend に送り `/api/i` で照合 — 毎回の外部API依存、失効管理が弱い。
  - (B) 自前 JWT — ステートレスで水平スケールに強いが、即時失効が困難。
- **帰結**: 即時失効が可能。単一オリジン運用なので CSRF 対策は `SameSite` で足りる。水平スケール時はセッションストアが共有点になるが、当面1ノードで非問題。Redis は不要（MariaDBで十分）。

---

## ADR-002 Misskeyアクセストークンの保管

- **ステータス**: ✅ Accepted
- **日付**: 2026-06-15
- **コンテキスト**: 「セキュア情報は基本保持しない」方針。マイページ表示に必要なのは identity のみ。
- **決定**: 照合に使用した Misskey トークンは**保持しない**。永続化するのは `misskey_id`、`misskey_host`（fediverse 識別のため）、表示用 `username` のみ。
- **検討した代替案**: トークンをDBに長期保存し、将来の Misskey API 呼び出しに使う。
- **帰結**: 他者トークンの長期保管という負債を排除。将来 Misskey 連携機能を増やす場合は、その時点で再認可（再MiAuth）で対応する。

---

## ADR-003 MariaDB の配置

- **ステータス**: ✅ Accepted
- **日付**: 2026-06-15
- **コンテキスト**: 複数ワールド → 複数ディメンション化に伴い **PlayerSync を廃止**するため、PlayerSync用の既存MariaDBは流用対象から外れる。連携データの書き込み元は Web 手動入力のみで、BDS（オンプレ）はこのDBに書かない。
- **決定**: 新規 MariaDB を **GCE A の既存 docker-compose スタック**（cloudflared / envoy / api と同居）にサービスとして追加。Ktor バックエンドとは compose ネットワーク内部で接続する（ホストポート非公開）。
- **検討した代替案**:
  - (A) Cloud SQL — マネージドだが月額増、FinOps 思想と逆行。
  - (C) 既存オンプレ k3s の MariaDB を流用 — PlayerSync 廃止で対象が消滅。
- **帰結**: コスト追加最小、Ktor と同一ネットワークで低レイテンシかつ単純。
  - **要追加定義**: 永続化ボリュームのバックアップ運用（GCE A の disk と DB ダンプ）。
  - **要追加定義**: `.env` への DB 資格情報の注入経路（v1は手動。将来 Secret Manager → cloud-init/Ansible）。

---

## ADR-004 ゲーム内アカウントの連携方式

- **ステータス**: ✅ Accepted
- **日付**: 2026-06-15
- **コンテキスト**: 「アカウント作成の簡易認証」であり、暗号学的な所有権証明は現規模で不要（詐称問題は不要と判断）。ADR-006 により XUID 等は使わず IGN（ゲーム内ユーザー名）ベース。
- **決定**: ワンタイムコード方式（`/verify` 等）は**採用しない**。Misskey 認証済みのマイページから、ユーザーが自身の IGN（Java / Bedrock それぞれ）を手動入力して連携する。
- **照合方法（確定）**: **(i) 純粋自己申告**。ユーザー入力 IGN をそのまま登録し、サーバーコンソールログは管理者の目視参照用に留める。自動存在チェック（ログ取込）は将来拡張。
- **検討した代替案**:
  - (A) ゲーム内ワンタイムコード → Web 貼付（業界標準）。
  - (B) Web 発行コード → ゲーム内 `/link`。
  - → いずれもプラグイン/MOD が前提であり、BDS（プラグイン不可）と整合しないため不採用。
- **帰結**: プラグイン/MOD 不要で実装が軽い。なりすまし耐性は無い（現規模で許容）。IGN 変更時には追従が必要。

---

## ADR-005 ゲーム内コマンドの実装場所

- **ステータス**: ⛔ Superseded（ADR-004 / ADR-006 により不要化）
- **日付**: 2026-06-15
- **決定**: ADR-004 でコード方式を採らないため、本機能において Velocity プラグイン / NeoForge MOD 等の実装は**不要**。
- **帰結**: プロキシ / サーバー側の改修ゼロ。将来「固有idベース識別」（ロードマップ）へ移行する際に、ここで Velocity プラグイン等を再検討する。

---

## ADR-006 Bedrock 身元の扱い

- **ステータス**: ✅ Accepted
- **日付**: 2026-06-15
- **コンテキスト**: Bedrock は BDS（`itzg/docker-minecraft-bedrock-server` で BDS 本体を取得）の独立駆動。Java 系プラグインは使用不可。
- **決定**: ユーザー認識はサーバーコンソールログの IGN を**初回に手動入力**して識別する。XUID は使用しない。現規模では詐称対策を行わない。
- **検討した代替案**:
  - Floodgate Global Linking で Java UUID を共有 / XUID（Floodgate UUID 形式 `00000000-0000-0000-xxxx-xxxxxxxxxxxx`）を固有IDとして保持。
  - → BDS 独立構成かつプラグイン不可のため、現時点では不適。
- **帰結**: 最小実装。
- **🗺 ロードマップ**: 規模拡大時に UUID / XUID 等の**固有idベース識別**へ移行する。ADR-008 の正規化スキーマ（`external_id` 列）がこの移行を許容する。

---

## ADR-007 新ロジックの設置場所

- **ステータス**: ✅ Accepted
- **日付**: 2026-06-15
- **コンテキスト**: 責任分担を重視。既存バックエンドは gRPC（メトリクス）で稼働中。認証・連携は Cookie 前提の素直な req/res。
- **決定**: 既存 Kotlin/Ktor バックエンドを拡張。認証・マイページ API は **REST ルート（`/api/*`）として追加**（gRPC-Web と Cookie は食い合わせが悪いため）。リアルタイムメトリクスは既存 gRPC のまま。
- **検討した代替案**: 新規マイクロサービス — 責務分離は明確だが運用点（コンテナ・デプロイ）が増える。
- **帰結**: 既存資産を活用しつつ責務を分離（**メトリクス = gRPC / 認証・連携 = REST**）。プロトコルは2系統になるが、責務が綺麗に分かれるため可読性はむしろ向上する。`/api` は Envoy の既存 `/` 経路（→ ktor_static :8080）に相乗りするため、Envoy 変更は不要。

---

## ADR-008 スキーマ設計

- **ステータス**: ✅ Accepted
- **日付**: 2026-06-15
- **コンテキスト**: 将来性の確保と、綺麗なスキーマの両立。
- **決定**: 正規化。中心 `users`（`misskey_id` キー）に対し、`linked_mc_accounts` を 1:N で持つ。セッションと監査を併設。

  ```
  users
    id (PK), misskey_id (UQ), misskey_host, username, created_at, updated_at

  linked_mc_accounts
    id (PK), user_id (FK->users), edition ('java'|'bedrock'),
    ign, external_id (nullable, 将来の UUID/XUID 用), linked_at
    UNIQUE(edition, ign)   ※同一IGNの重複登録防止

  sessions
    id (PK), token_hash (UQ, sha256), user_id (FK->users), expires_at, created_at

  link_audit
    id (PK), user_id, action ('link'|'unlink'), edition, ign, at, actor
  ```

- **検討した代替案**: `users` 単一テーブルに `java_ign` / `bedrock_ign` を nullable カラムで持つ — 単純だが「1垢=1人」固定で拡張性が低い。
- **帰結**: 1 Misskey : N MC垢に対応。`external_id` 列により固有idベースへの移行余地を確保。JOIN が1段増えるが無視可能。

---

## ADR-009 アカウントシステムの所有権モデル

- **ステータス**: ✅ Accepted（2026-06-15 確認）
- **日付**: 2026-06-15
- **コンテキスト**: MiAuth で SNS ユーザーとゲーム内ユーザーを紐付けたい。MiAuth が提供するのは identity のみで、アカウント・セッション・連携データは提供しない。
- **決定**: MiAuth を**外部IdP（ログイン手段）**として扱い、アカウント・セッションの権威は**自前バックエンド**が持つ（ソーシャルログイン → 自前アカウントパターン）。MiAuth は初回の identity 検証にのみ使用し、以降は自前セッション（ADR-001）で認証する。
- **検討した代替案**: Misskey トークンをそのままセッション代わりに使う — ADR-001/002 と矛盾し、失効・連携拡張に難。
- **帰結**: Misskey の可用性から独立、即時失効が可能、複数 identity 連携の余地。
- **付随する設計変更（現コードからの差分）**:
  1. MiAuth の `POST /api/miauth/<session>/check` は**バックエンド側で実施**し、セッション Cookie を発行する（現状のフロント実施から移行）。
  2. callback の `host` は信用せず、**サーバー側で `sushi.ski` に固定（allowlist）**する。

---

## 命名の正規化（ドリフト対策の前提メモ）

- 稼働中の成果物（Terraform / docker-compose / README / pubspec）はいずれも `tagomori-*` / `app.tagomori.dev` / `tagomori_status_frontend` で一致している。
- 例外: `infra/ansible/inventory.ini` の `sushiski-app` は Terraform が作る `tagomori-app` と不一致＝**既存ドリフト**。
- 「作業指示書」側で**正規名称テーブルを1つ固定**し、Claude Code がこの混在を増幅しないようにする（正規 = `tagomori-*`）。sushiski-* への改名を意図する場合は本機能とは別の専用タスクとする。

---

## 未決事項（Open Questions）

1. **ADR-003 のバックアップ運用** — MariaDB 永続化ボリュームのバックアップ方式（mysqldump → GCS 等）。
2. **DB 資格情報の注入経路** — v1 は手動で `~/app/.env` に登録（TUNNEL_TOKEN と同方式）。Secret Manager → cloud-init/Ansible への自動化は別タスク。
