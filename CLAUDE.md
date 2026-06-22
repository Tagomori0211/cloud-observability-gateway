# Tagomori Status Platform: 不変条件・開発ルール

## このリポジトリの不変条件（必ず守る）


## インフラデプロイチェックリスト
- このプロジェクトはOS Login付きセルフホストCIランナー経由でGCEにデプロイする。必ず以下を確認すること：(1) deploy.ymlにDB_PASSWORDなど必要なシークレットが実際に書き込まれているか、(2) OS LoginユーザーがusermodでDockerグループに追加されているか、(3) ランナーにunzip/jqがインストール済みか、(4) .envファイルがOS Loginユーザーの正しいホームディレクトリに配置されているか。

### 正規名称（勝手に改名しない）
- VM=tagomori-app / ドメイン=app.tagomori.dev / Flutterパッケージ=tagomori_status_frontend
- 新規DB名=tagomori_status / DBユーザー=app / composeサービス=mariadb
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
- 起動/再構築: `docker compose up -d --build`（docker-compose v1 禁止）
- envoy 検証: `docker run --rm -v $(pwd)/deploy/envoy.yaml:/envoy.yaml envoyproxy/envoy:v1.31.5 --mode validate -c /envoy.yaml`
- デプロイは CI/CD（main への push で自動実行）。
- main へ push したら、毎回 `gh` で CI/CD の進捗を確認・報告する（例: `gh run watch` / `gh run list`）。完了・失敗まで見届ける。
- skill-deployを実行

### 進め方
- 本書に無いファイルは触らない。1コミット=1論点。迷ったら止まって人間に聞く。
- 意思決定の根拠は `docs/ADR-account-linking.md`。本書と矛盾したら ADR を優先する。


