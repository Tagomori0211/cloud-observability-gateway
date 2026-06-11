# 作業指示書 v2: gRPC (Kotlin × Flutter Web) CI/CD 構築【Ktor相乗り + Cloudflare Tunnel版】

> 対象: Claude Code (Sonnet)
> 最終更新: 2026-06-11 JST
> リポジトリ: フロント (Flutter Web) + バックエンド (Kotlin / Ktor) のモノレポ
> ドメイン: tagomori.dev（取得済み・Cloudflare管理）。アプリは app.tagomori.dev を想定
> v1 からの変更点: TLS終端を Cloudflare エッジに移管。certbot / ACME / Envoy の TLS 設定を全廃し、
> cloudflared コンテナを追加。GCP ファイアウォールの 80/443 開放も不要に。

---

## 0. 全体アーキテクチャ（必読）

```
ブラウザ
  │ ① HTTPS :443（TLS は Cloudflare エッジが終端）
  ▼
Cloudflare Edge ══ CF Tunnel（アウトバウンド接続のみ）══► cloudflared コンテナ
                                                              │ 平文 HTTP
                                                              ▼
                                                          Envoy :80
                                                  ┌───────────┴───────────┐
                                        パス "/"                  パス "/shared."
                                              ▼                          ▼
                                      Ktor :8080                  Ktor :50051
                                  （Flutter Web 静的配信）      （gRPC, grpc_webフィルタで変換済）
                                                                          │
                                                                          ▼ ③ HTTP :8428（VPC内部）
                                                                  GCE B: VictoriaMetrics
```

**重要な前提知識（実装時に迷わないために）:**

- Flutter Web は `flutter build web` で生成される**ただの静的ファイル群**（index.html / main.dart.js / *.wasm 等）。サーバーサイドで実行されるものは何もない。ブラウザが初回にファイルをダウンロードし、以後はブラウザ内で動作。データ取得時のみ gRPC-Web リクエストが飛ぶ。
- Ktor プロセスは **1つの JVM 内で 2 ポート**を持つ:
  - `:8080` — Ktor (Netty) による静的ファイル配信
  - `:50051` — grpc-netty による gRPC サーバー
- いずれもホストへポート公開しない。外部との接点は **cloudflared のアウトバウンド接続のみ**。
- TLS は Cloudflare が終端する。**サーバー側に証明書は一切不要**（certbot 不要、更新 cron 不要）。
- `shared.proto`（リポジトリルート）が SSOT。Kotlin スタブは Gradle protobuf プラグインがビルド時に自動生成、Dart スタブは CI で protoc 手動実行。
- 同一オリジン（app.tagomori.dev のみ）運用のため **CORS は発生しない**。envoy.yaml の CORS 設定は将来のドメイン分離に備えた保険。
- **CF 経由の通信は無通信約100秒で切断される**点に注意。長時間沈黙する gRPC サーバーストリーミングを実装する場合は、サーバーから定期的に keepalive 相当のメッセージを送る設計にすること。

---

## 1. 成果物として作成するファイル一覧

```
リポジトリルート/
├── shared.proto                      # 既存（SSOT）。無ければ仮のサービス定義を作成
├── .github/workflows/deploy.yml     # 【作成】CI/CD ワークフロー
├── backend/
│   ├── build.gradle.kts              # 【作成/改修】protobuf プラグイン + shadowJar 設定
│   ├── settings.gradle.kts           # 【作成/改修】
│   └── src/main/kotlin/app/Main.kt   # 【作成/改修】Ktor静的配信 + gRPCサーバー起動
├── frontend/                         # 既存 Flutter プロジェクト
│   └── lib/src/generated/            # 【CI が生成】Dart スタブ出力先（.gitignore に追加）
└── deploy/
    ├── docker-compose.yml            # 【作成】cloudflared + Envoy + Ktor の3コンテナ構成
    ├── envoy.yaml                    # 【作成】gRPC-Web変換 / ルーティング（TLSなし）
    └── Dockerfile.api                # 【作成】fat JAR を載せるだけの薄いイメージ
```

実装順序: **backend → deploy → workflow** の順で進めること。

---

## 2. タスク詳細

### Task 1: backend/build.gradle.kts — Gradle protobuf プラグイン設定

要件:
- ルートの `../shared.proto` を proto ソースとして取り込み、`java` + `kotlin` + `grpc` + `grpckt` のスタブを生成
- shadowJar で fat JAR（`*-all.jar`）を出力
- JDK 21 / Kotlin 2.x 前提

```kotlin
// backend/build.gradle.kts
import com.google.protobuf.gradle.id

plugins {
    kotlin("jvm") version "2.0.21"
    id("com.google.protobuf") version "0.9.4"
    id("com.github.johnrengelman.shadow") version "8.1.1"
    application
}

group = "app"
version = "1.0.0"

repositories { mavenCentral() }

val ktorVersion = "2.3.12"
val grpcVersion = "1.66.0"
val grpcKotlinVersion = "1.4.1"
val protobufVersion = "4.27.3"

dependencies {
    // Ktor（静的ファイル配信用）
    implementation("io.ktor:ktor-server-core:$ktorVersion")
    implementation("io.ktor:ktor-server-netty:$ktorVersion")

    // gRPC
    implementation("io.grpc:grpc-netty-shaded:$grpcVersion")
    implementation("io.grpc:grpc-protobuf:$grpcVersion")
    implementation("io.grpc:grpc-kotlin-stub:$grpcKotlinVersion")
    implementation("com.google.protobuf:protobuf-kotlin:$protobufVersion")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")

    // ロギング
    implementation("ch.qos.logback:logback-classic:1.5.8")
}

application {
    mainClass.set("app.MainKt")
}

java {
    toolchain { languageVersion.set(JavaLanguageVersion.of(21)) }
}

// ---- SSOT: リポジトリルートの shared.proto を取り込む ----
sourceSets {
    main {
        proto {
            srcDir("../")
            include("shared.proto")
        }
    }
}

protobuf {
    protoc { artifact = "com.google.protobuf:protoc:$protobufVersion" }
    plugins {
        id("grpc")   { artifact = "io.grpc:protoc-gen-grpc-java:$grpcVersion" }
        id("grpckt") { artifact = "io.grpc:protoc-gen-grpc-kotlin:$grpcKotlinVersion:jdk8@jar" }
    }
    generateProtoTasks {
        all().forEach {
            it.plugins {
                id("grpc")
                id("grpckt")
            }
            it.builtins {
                id("kotlin")
            }
        }
    }
}
```

```kotlin
// backend/settings.gradle.kts
rootProject.name = "backend"
```

### Task 2: backend/src/main/kotlin/app/Main.kt — 1プロセス2ポート

要件:
- `:50051` で gRPC サーバー起動（shared.proto のサービス実装を登録）
- `:8080` で Ktor 起動。SPA フォールバック付きで `/app/web` を配信
- VictoriaMetrics の URL は環境変数 `VICTORIA_METRICS_URL` から取得
- v1 にあった ACME チャレンジ配信は **不要**（CF Tunnel のため）

```kotlin
// backend/src/main/kotlin/app/Main.kt
package app

import io.grpc.ServerBuilder
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.http.content.*
import io.ktor.server.routing.*

fun main() {
    val vmUrl = System.getenv("VICTORIA_METRICS_URL") ?: "http://localhost:8428"

    // ---- gRPC サーバー :50051 ----
    // ※ SharedServiceImpl は shared.proto のサービス定義に対応する実装クラス。
    //    生成された <Service名>GrpcKt.<Service名>CoroutineImplBase を継承して実装すること。
    val grpcServer = ServerBuilder
        .forPort(50051)
        .addService(SharedServiceImpl(vmUrl))
        .build()
        .start()
    println("gRPC server started on :50051")

    // ---- Ktor 静的配信 :8080 ----
    embeddedServer(Netty, port = 8080) {
        routing {
            // Flutter Web（SPA フォールバック: 未知のパスは index.html へ）
            singlePageApplication {
                useResources = false
                filesPath = "/app/web"
                defaultPage = "index.html"
            }
        }
    }.start(wait = false)
    println("Static file server started on :8080")

    grpcServer.awaitTermination()
}
```

注意: `SharedServiceImpl` の中身は shared.proto の定義に依存するため、proto を読んでから生成クラス名に合わせて実装すること。仮実装でよいので必ずコンパイルが通る状態にすること。

### Task 3: deploy/Dockerfile.api

```dockerfile
# deploy/Dockerfile.api
# CI でビルド済みの fat JAR を載せるだけ。ビルドの実体は GitHub Actions 側。
FROM eclipse-temurin:21-jre-jammy

WORKDIR /app
COPY app.jar /app/app.jar

# 8080: 静的配信 / 50051: gRPC（いずれも compose ネットワーク内のみ）
EXPOSE 8080 50051

ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "/app/app.jar"]
```

### Task 4: deploy/docker-compose.yml

```yaml
# deploy/docker-compose.yml
# GCE A 上のランタイム: cloudflared + Envoy + Ktor の3コンテナ
#
# 前提:
#   - Cloudflare Zero Trust で Tunnel 作成済み、TUNNEL_TOKEN を取得済み
#   - GCE A 上の ~/app/.env に TUNNEL_TOKEN=eyJ... を記載（git管理外・rsync除外）
#   - Tunnel の Public Hostname 設定（CFダッシュボード側）:
#       app.tagomori.dev → http://envoy:80
#   - GCP ファイアウォール: インバウンドは tcp:22（CI の SSH デプロイ用）のみ。
#     80/443 は開けない（cloudflared がアウトバウンドで張るため不要）

services:
  # ---- Cloudflare Tunnel（外部との唯一の接点）----
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: app-cloudflared
    command: tunnel --no-autoupdate run
    environment:
      TUNNEL_TOKEN: ${TUNNEL_TOKEN}
    depends_on:
      - envoy
    restart: unless-stopped

  # ---- gRPC-Web 変換 / ルーティング ----
  envoy:
    image: envoyproxy/envoy:v1.31.5
    container_name: app-envoy
    volumes:
      - ./envoy.yaml:/etc/envoy/envoy.yaml:ro
    depends_on:
      - api
    restart: unless-stopped
    # ports は定義しない。cloudflared からのみ到達（envoy:80）。

  # ---- Kotlin (Ktor + grpc-kotlin) バックエンド ----
  api:
    build:
      context: ./api   # CI が配置した app.jar + Dockerfile
    container_name: app-api
    environment:
      VICTORIA_METRICS_URL: "http://10.146.0.X:8428"   # ← GCE B のプライベートIPに置換
    volumes:
      - ./web:/app/web:ro   # Flutter Web アセット（rsync で更新、イメージ再ビルド不要）
    restart: unless-stopped
    # ports は定義しない。8080/50051 は compose ネットワーク内のみ。
    # 注意: networks に internal: true を付けないこと。
    #       cloudflared のアウトバウンド接続と GCE B への VPC 内部通信が両方塞がる。
```

### Task 5: deploy/envoy.yaml

```yaml
# deploy/envoy.yaml
# 役割: gRPC-Web → 生gRPC 変換 / パスルーティング
#   /shared.*  → api:50051 (gRPC, h2c)
#   /*         → api:8080  (Ktor 静的配信)
#
# v1 との差分: TLS終端は Cloudflare エッジが担うため、
# TLS設定・ACMEリスナー(:80のリダイレクト)・証明書マウントをすべて削除。
# Envoy は平文 HTTP :80 のみ listen し、cloudflared からの接続だけを受ける。

static_resources:
  listeners:
    - name: listener_http
      address:
        socket_address: { address: 0.0.0.0, port_value: 80 }
      filter_chains:
        - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                stat_prefix: ingress_http
                codec_type: AUTO
                use_remote_address: true
                route_config:
                  name: app_routes
                  virtual_hosts:
                    - name: app
                      domains: ["*"]
                      # 同一オリジン運用では CORS は発生しない。将来分離時の保険。
                      typed_per_filter_config:
                        envoy.filters.http.cors:
                          "@type": type.googleapis.com/envoy.extensions.filters.http.cors.v3.CorsPolicy
                          allow_origin_string_match:
                            - exact: "https://app.tagomori.dev"
                          allow_methods: "GET, POST, OPTIONS"
                          allow_headers: "keep-alive,user-agent,cache-control,content-type,content-transfer-encoding,x-grpc-web,grpc-timeout,authorization"
                          expose_headers: "grpc-status,grpc-message"
                          max_age: "1728000"
                      routes:
                        # gRPC-Web → Ktor :50051
                        # パスは /shared.ServiceName/Method 形式（package 名 = shared 前提）
                        - match: { prefix: "/shared." }
                          route:
                            cluster: grpc_backend
                            timeout: 0s   # ストリーミングRPC対策（デフォルト15秒で切断される）
                            max_stream_duration:
                              grpc_timeout_header_max: 0s
                        # それ以外 → Ktor :8080（静的配信）
                        - match: { prefix: "/" }
                          route: { cluster: ktor_static }
                http_filters:
                  # 順序重要: grpc_web → cors → router
                  - name: envoy.filters.http.grpc_web
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.filters.http.grpc_web.v3.GrpcWeb
                  - name: envoy.filters.http.cors
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.filters.http.cors.v3.Cors
                  - name: envoy.filters.http.router
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

  clusters:
    # Ktor gRPC（HTTP/2 必須）
    - name: grpc_backend
      type: STRICT_DNS
      lb_policy: ROUND_ROBIN
      typed_extension_protocol_options:
        envoy.extensions.upstreams.http.v3.HttpProtocolOptions:
          "@type": type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions
          explicit_http_config:
            http2_protocol_options: {}   # api へは h2c（平文 HTTP/2）
      load_assignment:
        cluster_name: grpc_backend
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address: { address: api, port_value: 50051 }

    # Ktor 静的配信（HTTP/1.1）
    - name: ktor_static
      type: STRICT_DNS
      lb_policy: ROUND_ROBIN
      load_assignment:
        cluster_name: ktor_static
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address: { address: api, port_value: 8080 }
```

### Task 6: .github/workflows/deploy.yml

```yaml
# .github/workflows/deploy.yml
# main プッシュ → proto生成 → Kotlin/Flutterビルド → GCE A へ rsync → docker compose 再構築
#
# 必要な GitHub Secrets:
#   GCE_HOST_IP  : GCE A のパブリックIP（SSH 用。HTTP は CF Tunnel 経由のため不使用）
#   GCE_SSH_USER : デプロイ用ユーザー（docker グループ所属必須）
#   GCE_SSH_KEY  : SSH 秘密鍵（OpenSSH形式）

name: Deploy to GCE

on:
  push:
    branches: [main]

concurrency:
  group: deploy-production
  cancel-in-progress: false

env:
  DEPLOY_DIR: /home/${{ secrets.GCE_SSH_USER }}/app

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 30

    steps:
      - uses: actions/checkout@v4

      # ---- proto 生成（Dart のみ。Kotlin は Gradle が自動生成）----
      - name: Setup protoc
        uses: arduino/setup-protoc@v3
        with:
          version: "27.x"
          repo-token: ${{ secrets.GITHUB_TOKEN }}

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Generate Dart stubs
        run: |
          dart pub global activate protoc_plugin
          export PATH="$PATH:$HOME/.pub-cache/bin"
          mkdir -p frontend/lib/src/generated
          protoc \
            --proto_path=. \
            --dart_out=grpc:frontend/lib/src/generated \
            shared.proto

      # ---- バックエンドビルド ----
      - name: Setup JDK 21
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "21"

      - name: Setup Gradle
        uses: gradle/actions/setup-gradle@v4

      - name: Build fat JAR
        working-directory: backend
        run: ./gradlew --no-daemon shadowJar

      # ---- フロントエンドビルド ----
      # 注意: --web-renderer フラグは Flutter 3.29 で削除済み。付けるとエラー。
      - name: Build Flutter Web
        working-directory: frontend
        run: |
          flutter pub get
          flutter build web --release

      # ---- バンドル組み立て ----
      - name: Assemble deploy bundle
        run: |
          mkdir -p bundle/api bundle/web
          cp backend/build/libs/*-all.jar  bundle/api/app.jar
          cp deploy/Dockerfile.api         bundle/api/Dockerfile
          cp -r frontend/build/web/.       bundle/web/
          cp deploy/docker-compose.yml     bundle/
          cp deploy/envoy.yaml             bundle/

      # ---- 転送 ----
      # --delete で古いハッシュ付きアセットを掃除。
      # --exclude=.env でサーバー側の TUNNEL_TOKEN を保護（消したら Tunnel が死ぬ）。
      - name: Sync bundle to GCE
        uses: burnett01/rsync-deployments@7.0.2
        with:
          switches: -avzr --delete --exclude=.env
          path: bundle/
          remote_path: ${{ env.DEPLOY_DIR }}/
          remote_host: ${{ secrets.GCE_HOST_IP }}
          remote_user: ${{ secrets.GCE_SSH_USER }}
          remote_key: ${{ secrets.GCE_SSH_KEY }}

      # ---- リモート再構築 ----
      # down は使わない（全停止＝無駄なダウンタイム）
      - name: Rebuild containers on GCE
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.GCE_HOST_IP }}
          username: ${{ secrets.GCE_SSH_USER }}
          key: ${{ secrets.GCE_SSH_KEY }}
          script: |
            set -euo pipefail
            cd ${{ env.DEPLOY_DIR }}
            docker compose up -d --build
            # envoy.yaml は bind mount のため内容変更だけでは再読込されない
            docker compose restart envoy
            docker image prune -f
```

---

## 3. 実装時の注意事項（重要）

1. **`flutter build web` に `--web-renderer` を付けないこと。** Flutter 3.29 で削除されたフラグであり、付けると CI が落ちる。canvaskit は現行デフォルト。
2. **Envoy ルートの `timeout: 0s` を消さないこと。** ストリーミング RPC がデフォルト15秒で切断される。
3. **CF 経由の通信は無通信約100秒で切断される。** 長時間沈黙する gRPC サーバーストリーミングを使う場合は、サーバー側から定期的にメッセージを送る（heartbeat）設計にすること。CF のアップロードボディ上限（Free プランで 100MB）にも留意。
4. **`docker-compose`（ハイフン付き v1）コマンドを書かないこと。** すべて `docker compose`（v2）で統一。
5. **`networks: internal: true` を compose に追加しないこと。** cloudflared のアウトバウンド接続と GCE B への VPC 内部通信が両方塞がる。
6. **rsync の `--exclude=.env` を消さないこと。** サーバー側 `.env` には TUNNEL_TOKEN が入っており、`--delete` で消すと Tunnel が落ちる。`.env` は git にもコミットしないこと。
7. **Dart スタブの出力先 `frontend/lib/src/generated/` は .gitignore に追加すること**（CI 生成物のため）。ローカル開発時は同じ protoc コマンドを手元で実行する。
8. **Flutter 側の gRPC 接続先はオリジン相対にすること。** `GrpcWebClientChannel.xhr(Uri.base.origin)` のようにし、URL のハードコードを避ける（同一オリジン運用のため）。
9. Ktor 3.x 系を使う場合、`singlePageApplication` の API が変わっている可能性があるため公式ドキュメントを確認すること。
10. shared.proto が未作成の場合は `syntax = "proto3"; package shared;` で始まる仮のサービス定義（unary RPC を1つ）を作成し、フロント・バック双方で疎通確認ができる最小構成とすること。

---

## 4. 初回のみ必要なセットアップ（手動・Claude Code の作業範囲外）

### Cloudflare 側（ダッシュボード）

1. Zero Trust > Networks > Tunnels で新規 Tunnel を作成（例: `gce-a-app`）し、**TUNNEL_TOKEN を控える**
2. Tunnel の Public Hostname を追加:
   - Subdomain: `app` / Domain: `tagomori.dev` / Service: `http://envoy:80`
   - ※ Service のホスト名は **compose のサービス名 `envoy`**（cloudflared が同一 Docker ネットワーク内から名前解決するため）
3. monitor.tagomori.dev は別 Tunnel（自宅ラボ側）として従来計画どおり運用。
   軌道に乗ったら duckdns 側の廃止も検討可

### GCE A 側

```bash
# 1. Docker / compose v2 導入（公式手順に従う）
# 2. デプロイ用ディレクトリ作成
mkdir -p ~/app

# 3. TUNNEL_TOKEN を配置（git 管理外・rsync 除外対象）
echo 'TUNNEL_TOKEN=eyJxxxx...' > ~/app/.env
chmod 600 ~/app/.env

# 4. GCP ファイアウォール: インバウンドは tcp:22 のみ許可。
#    80 / 443 / 50051 は開けない。
#    （余裕があれば 22 の送信元を制限。将来的には IAP や CF Access で 22 も閉鎖可能）
```

---

## 5. 受け入れ条件（Definition of Done）

- [ ] `cd backend && ./gradlew shadowJar` がローカルで成功し、`build/libs/*-all.jar` が生成される（proto スタブ自動生成込み）
- [ ] `Main.kt` がコンパイルされ、起動時に :8080 と :50051 の両方が listen する
- [ ] `protoc --dart_out=grpc:...` が shared.proto から Dart スタブを生成できる
- [ ] `flutter build web --release` が成功する
- [ ] deploy.yml の YAML 構文が valid（actionlint 推奨）
- [ ] envoy.yaml が検証を通過する:
      `docker run --rm -v $(pwd)/deploy/envoy.yaml:/envoy.yaml envoyproxy/envoy:v1.31.5 --mode validate -c /envoy.yaml`
- [ ] README またはコメントに「app.tagomori.dev」「GCE B の IP」「TUNNEL_TOKEN の配置場所」が明記されている
- [ ] `.gitignore` に `frontend/lib/src/generated/` と `.env` が含まれている

## 6. 動作確認手順（デプロイ後）

```bash
# Tunnel の接続確認
docker compose logs cloudflared   # "Registered tunnel connection" が出ていること

# 静的配信の確認
curl -I https://app.tagomori.dev/   # 200 + text/html（cf-ray ヘッダが付いていればCF経由）

# gRPC-Web ルーティングの確認
# ブラウザ DevTools > Network で /shared.Xxx/Method へのリクエストが
# Content-Type: application/grpc-web+proto で 200 になっていること

# ログ確認
docker compose logs -f envoy
docker compose logs -f api
```