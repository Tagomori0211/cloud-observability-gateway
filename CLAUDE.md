# Tagomori Status Platform: 不変条件・開発ルール

## このリポジトリの不変条件（必ず守る）


## インフラデプロイチェックリスト
- このプロジェクトはセルフホストCIランナーから Tailscale 経由の SSH で k3s-worker（オンプレ k3s）にデプロイする。必ず以下を確認すること：(1) deploy.ymlにDB_PASSWORDなど必要なシークレットが実際に書き込まれているか（Secret tagomori-status-db へ同期される）、(2) K3S_SSH_KEY / K3S_KNOWN_HOSTS が登録済みで、公開鍵が k3s-worker の shinari の authorized_keys にあるか、(3) ランナーにunzip/jq/rsyncがインストール済みか、(4) 手動作成の Secret（cloudflared-token / gcp-credentials）が namespace tagomori-status に存在するか。

### 正規名称（勝手に改名しない）
- 実行基盤=k3s-worker（namespace tagomori-status）/ ドメイン=app.tagomori.dev / Flutterパッケージ=tagomori_status_frontend
  - 2026-09-30 に GCE（mc-gateway、旧 tagomori-app）から k3s-worker へ移設。mc-gateway は Minecraft 入口・監視スタック（VictoriaMetrics）の VM として残り、Minecraft-on-Kubernetes の `Terraform/gateway.tf` が管理する。docs/ 配下の tagomori-app 表記は当時の記録。
- 新規DB名=tagomori_status / DBユーザー=app / composeサービス・k8s Service=mariadb
- ansible の sushiski-app は既存ドリフト。触らない・複製しない。

### アーキテクチャの分界（ADR-007）
- メトリクス = gRPC（:50051, /shared.*）。**既存・不変。触らない。**
- 認証・連携 = REST（/api/*, :8080）。新機能はこちらにのみ足す。
- /api は Envoy の既存 / 経路に相乗り。envoy.yaml は変更しない。

### 認証方式（ADR-010・最新）
- MiAuth は**初回登録時の本人確認専用**。再ログインは ID（=Misskey username）/ パスワードで行う。
- パスワードは bcrypt（jBCrypt）でハッシュ化し `users.password_hash` に保存。平文は保持・ログ出力しない。

### セキュリティ（ADR-002 / 009 / 010）
- Misskey トークンを永続化しない。保存するのは misskey_id / host / username / password_hash のみ。
- MiAuth の host は sushi.ski に固定。callback の host を信用しない。
- 秘密情報をコード・ログ・レスポンス・コミットに出さない。.env は読まない・書かない。
- DB アクセスは repository 層経由のみ。SQL は prepared statement のみ（文字列連結禁止）。

### 触るな
- shared.proto / SharedServiceImpl.kt / metrics_grpc_service.dart / envoy.yaml
- cloudflared 関連 / infra/** / frontend/lib/src/generated/**

### コマンド規約
- ビルド(backend): `cd backend && ./gradlew --no-daemon shadowJar`
- ビルド(frontend): `cd frontend && flutter pub get && flutter build web --release`（--web-renderer 禁止）
- 起動/再構築（ローカル）: `docker compose up -d --build`（docker-compose v1 禁止）
- 本番の状態確認: `ssh k3s-worker 'sudo kubectl -n tagomori-status get pods'`
- envoy 検証: `docker run --rm -v $(pwd)/deploy/envoy.yaml:/envoy.yaml envoyproxy/envoy:v1.31.5 --mode validate -c /envoy.yaml`
- デプロイは CI/CD（main への push で自動実行）。
- main へ push したら、毎回 `gh` で CI/CD の進捗を確認・報告する（例: `gh run watch` / `gh run list`）。完了・失敗まで見届ける。
- skill-deployを実行

### 進め方
- 本書に無いファイルは触らない。1コミット=1論点。迷ったら止まって人間に聞く。
- 意思決定の根拠は `docs/ADR-account-linking.md`。本書と矛盾したら ADR を優先する。


