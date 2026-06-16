# sushiski Status Platform: 不変条件・開発ルール (GEMINI)

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
