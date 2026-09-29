Proxmox 基盤の上に IaC（Terraform 等）で k3s を立て、既存 Minecraft 基盤に相乗りして本アプリ（Status Platform）を載せている。

<div align="center">

# 🖥️ Status Platform

**Minecraft サーバー監視ダッシュボード**

Flutter Web フロントエンド × Kotlin (Ktor / grpc-kotlin) バックエンド

[![Flutter](https://img.shields.io/badge/Frontend-Flutter%20Web-02569B?style=flat-square&logo=flutter&logoColor=white)](frontend/)
[![Kotlin](https://img.shields.io/badge/Backend-Kotlin%20%2F%20Ktor-7F52FF?style=flat-square&logo=kotlin&logoColor=white)](backend/)
[![gRPC](https://img.shields.io/badge/API-gRPC--Web-244c5a?style=flat-square&logo=google&logoColor=white)](shared.proto)
[![Envoy](https://img.shields.io/badge/Proxy-Envoy-ac6199?style=flat-square&logo=envoyproxy&logoColor=white)](deploy/envoy.yaml)
[![Cloudflare](https://img.shields.io/badge/Edge-Cloudflare%20Tunnel-F38020?style=flat-square&logo=cloudflare&logoColor=white)](#1-cloudflare手動)
[![Terraform](https://img.shields.io/badge/IaC-Terraform-844FBA?style=flat-square&logo=terraform&logoColor=white)](infra/terraform/)
[![GCP](https://img.shields.io/badge/Cloud-GCE-4285F4?style=flat-square&logo=googlecloud&logoColor=white)](#アーキテクチャ)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

🌐 公開 URL: **[https://app.tagomori.dev](https://app.tagomori.dev)**（Cloudflare Tunnel 経由・予定）

</div>

> [!NOTE]
> 既存インフラ [Minecraft-on-Kubernetes](https://github.com/Tagomori0211/Minecraft-on-Kubernetes) に相乗りする形で構築。
> 実行 VM（`mc-gateway`）とメトリクスソースの VictoriaMetrics は同リポジトリが管理する**既存リソース**。

---

## 📑 目次

- [アーキテクチャ](#-アーキテクチャ)
- [リポジトリ構成](#-リポジトリ構成)
- [シークレットの取り扱い](#-シークレットの取り扱い)
- [初回セットアップ](#-初回セットアップ)
- [ローカル開発](#-ローカル開発)
- [動作確認（デプロイ後）](#-動作確認デプロイ後)
- [ライセンス](#-ライセンス)

---

## 🗺 アーキテクチャ

```mermaid
flowchart TD
    %% ============ ノード定義 ============
    Browser["🌐 ブラウザ<br/>(ユーザー)"]

    subgraph CF["☁️ Cloudflare"]
        Edge["Cloudflare Edge<br/>🔒 TLS 終端"]
    end

    subgraph GW["🖥️ GCE: mc-gateway（e2-micro・Minecraft 入口 / 監視と同居）"]
        subgraph VM1["Status Platform（Docker Compose・~/app）"]
            Cloudflared["cloudflared コンテナ<br/>（Tunnel クライアント）"]
            Envoy["⚙️ Envoy :80<br/>リバースプロキシ / ルーティング"]
            KtorWeb["🎯 Ktor :8080<br/>Flutter Web 静的配信"]
            KtorGrpc["🔌 Ktor :50051<br/>gRPC バックエンド<br/>（grpc_web フィルタで変換済）"]
        end

        subgraph VM2["📊 監視スタック（/opt/mc-gateway・host network）"]
            VM["VictoriaMetrics :8428"]
        end
    end

    %% ============ エッジ定義 ============
    Browser -- "① HTTPS :443<br/>（TLS は CF エッジが終端）" --> Edge
    Edge == "CF Tunnel<br/>⬅️ アウトバウンド接続のみ" ==> Cloudflared
    Cloudflared -- "平文 HTTP" --> Envoy
    Envoy -- "📄 パス  /" --> KtorWeb
    Envoy -- "📡 パス  /shared." --> KtorGrpc
    KtorGrpc -- "② HTTP :8428<br/>（同一ホスト・host.docker.internal）" --> VM

    %% ============ スタイル定義 ============
    classDef browser fill:#1a73e8,stroke:#0b3d91,stroke-width:3px,color:#ffffff,font-weight:bold
    classDef cloudflare fill:#f38020,stroke:#b35900,stroke-width:3px,color:#ffffff,font-weight:bold
    classDef tunnel fill:#fad02c,stroke:#b8860b,stroke-width:3px,color:#222222,font-weight:bold
    classDef envoy fill:#ac6199,stroke:#6d2f63,stroke-width:3px,color:#ffffff,font-weight:bold
    classDef ktorweb fill:#00bfa5,stroke:#00695c,stroke-width:3px,color:#ffffff,font-weight:bold
    classDef ktorgrpc fill:#2e7d32,stroke:#1b4d1e,stroke-width:3px,color:#ffffff,font-weight:bold
    classDef metrics fill:#d32f2f,stroke:#7f1010,stroke-width:3px,color:#ffffff,font-weight:bold

    class Browser browser
    class Edge cloudflare
    class Cloudflared tunnel
    class Envoy envoy
    class KtorWeb ktorweb
    class KtorGrpc ktorgrpc
    class VM metrics

    %% サブグラフの背景色
    style CF fill:#fff3e0,stroke:#f38020,stroke-width:2px
    style GW fill:#f8f9fa,stroke:#5f6368,stroke-width:2px
    style VM1 fill:#e8f0fe,stroke:#1a73e8,stroke-width:2px,stroke-dasharray:5 5
    style VM2 fill:#fdecea,stroke:#d32f2f,stroke-width:2px,stroke-dasharray:5 5

    %% エッジの色分け
    linkStyle 0 stroke:#1a73e8,stroke-width:3px
    linkStyle 1 stroke:#f38020,stroke-width:4px
    linkStyle 2 stroke:#888888,stroke-width:2px,stroke-dasharray:4 4
    linkStyle 3 stroke:#00bfa5,stroke-width:3px
    linkStyle 4 stroke:#2e7d32,stroke-width:3px
    linkStyle 5 stroke:#d32f2f,stroke-width:3px
```

### 構成要素

| リソース | 役割 | 管理元 |
|---|---|---|
| 🖥️ **mc-gateway**（GCE e2-micro） | cloudflared + Envoy + Ktor + MariaDB を Docker Compose（`~/app`）で運用。Minecraft 入口の socat・監視スタックと同じ VM | 🔒 **既存リソース**（Minecraft-on-Kubernetes の `Terraform/gateway.tf`）。本リポジトリは CI でアプリを配置するのみ |
| 📊 **VictoriaMetrics**（mc-gateway 上の :8428） | メトリクスソース | 🔒 **既存リソース**（Minecraft-on-Kubernetes の `gce/gateway/`）。本リポジトリでは触らない |
| 🔑 CI 用 SA / WIF / Secret skeleton | GitHub Actions からの IAP SSH デプロイ | ✅ 本リポジトリの Terraform（`infra/terraform/`） |

### ネットワーク / セキュリティ設計

- 🔐 Ktor → VictoriaMetrics は同じ VM 内（`host.docker.internal:8428`）で完結し、VPC 越しの通信や専用ファイアウォールは不要
- 📜 **TLS 証明書はサーバー側に一切不要**（Cloudflare が終端）
- 🚪 本アプリ用のインバウンドは開けない（80/443 不要）。CI は IAP SSH（`minecraft` タグ向けの既存ルール）で接続する

---

## 📂 リポジトリ構成

```
├── shared.proto                  # gRPC SSOT（MetricsService: GetMetrics / StreamMetrics）
├── frontend/                     # Flutter Web
│   └── lib/
│       ├── screens/status_screen.dart      # メインダッシュボード（30秒ポーリング）
│       ├── services/metrics_service.dart   # HTTP フォールバック（現行）
│       ├── services/metrics_grpc_service.dart  # gRPC-Web（スタブ生成後に有効化）
│       ├── models/ / widgets/ / theme/
│       └── src/generated/        # Dart スタブ出力先（CI生成・git管理外）
├── backend/                      # Kotlin / Ktor / grpc-kotlin
│   └── src/main/kotlin/app/
│       ├── Main.kt               # 1プロセス2ポート（:8080 静的配信 / :50051 gRPC）
│       └── SharedServiceImpl.kt  # VictoriaMetrics クエリ → gRPC レスポンス
├── deploy/
│   ├── docker-compose.yml        # cloudflared + Envoy + Ktor + MariaDB
│   ├── envoy.yaml                # gRPC-Web 変換 / パスルーティング
│   └── Dockerfile.api            # fat JAR を載せる薄いイメージ
├── infra/
│   ├── terraform/                # CI 用 SA / WIF・Secret skeleton（VM は持たない）
│   └── ansible/                  # 旧 tagomori-app 向けロール（mc-gateway 統合後は未使用）
└── .github/workflows/deploy.yml  # CI/CD（IAP SSH 経由デプロイ）
```

---

## 🔑 シークレットの取り扱い

| シークレット | 保管場所 | 備考 |
|---|---|---|
| `TUNNEL_TOKEN` | 🗄️ Secret Manager: `tagomori-tunnel-token` | CI が mc-gateway の `~/app/.env`（mode 600）に未設定時のみ追記。git 管理外・デプロイ時も削除しない |
| `VICTORIA_METRICS_URL` | 📄 `~/app/.env`（CI が生成） | 既定値 `http://host.docker.internal:8428`（同じ VM の VictoriaMetrics） |
| CI 用 SA キー | 🐙 GitHub Secrets: `GCP_CI_SA_KEY` | `terraform output -raw ci_sa_key_b64` で取得 |

> [!WARNING]
> **`.env` は絶対にコミットしない。** テンプレートは [.env.example](.env.example) を参照。

---

## 🚀 初回セットアップ

### 1. Cloudflare（手動）

1. **Zero Trust > Networks > Tunnels** で Tunnel 作成 → `TUNNEL_TOKEN` を控える
2. **Public Hostname** 追加: `app.tagomori.dev` → `http://envoy:80`（compose サービス名で指定）

### 2. Terraform

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # project_id を記入
terraform init && terraform apply
```

| 作成されるもの | 既存リソース（data source 参照のみ・変更しない） |
|---|---|
| `tagomori-tunnel-token` skeleton / CI 用 SA（`tagomori-ci-sa`）と IAM / WIF（`github-pool`） | `mc-proxy-sa`（mc-gateway の VM SA） |

実行 VM `mc-gateway` は Minecraft-on-Kubernetes の Terraform（`Terraform/gateway.tf`）が作成する。

### 3. シークレット登録

```bash
# Cloudflare で取得したトークンを登録（CI がデプロイ時に mc-gateway の .env へ展開する）
gcloud secrets versions add tagomori-tunnel-token --data-file=- <<< "eyJ..."
```

### 4. GitHub Secrets

| Secret | 値 |
|---|---|
| `GCP_CI_SA_KEY` | `terraform output -raw ci_sa_key_b64` の出力 |
| `GCP_PROJECT_ID` | GCP プロジェクト ID |
| `GCE_ZONE` | `asia-northeast1-b` |
| `GCE_SSH_USER` | CI SA の OS Login ユーザー名（`sa_<数字>` 形式） |

### 5. デプロイ

`main` にプッシュすると CI が以下を自動実行する:

```mermaid
flowchart LR
    A["📦 proto 生成"] --> B["🛠️ Kotlin / Flutter<br/>ビルド"] --> C["🔐 IAP 経由で転送"] --> D["🐳 docker compose<br/>up -d --build"]

    classDef step fill:#1a73e8,stroke:#0b3d91,stroke-width:2px,color:#ffffff,font-weight:bold
    class A,B,C,D step
```

---

## 💻 ローカル開発

```bash
# フロントエンド（HTTP フォールバックで動作。/api/metrics をモックするか CORS 許可が必要）
cd frontend && flutter pub get && flutter run -d chrome

# バックエンド（fat JAR ビルド。proto スタブは Gradle が自動生成）
cd backend && ./gradlew shadowJar

# Dart スタブ手動生成（gRPC-Web へ切り替える場合）
dart pub global activate protoc_plugin
protoc --proto_path=. --dart_out=grpc:frontend/lib/src/generated shared.proto

# envoy.yaml 構文検証
docker run --rm -v $(pwd)/deploy/envoy.yaml:/envoy.yaml envoyproxy/envoy:v1.31.5 --mode validate -c /envoy.yaml
```

---

## ✅ 動作確認（デプロイ後）

| # | 確認項目 | コマンド / 手順 | 期待結果 |
|---|---|---|---|
| 1 | 🌩️ Tunnel 接続 | （mc-gateway の `~/app` で）`docker compose logs cloudflared` | `Registered tunnel connection` が出る |
| 2 | 📄 静的配信 | `curl -I https://app.tagomori.dev/` | `200` + `text/html`、`cf-ray` ヘッダ付きなら CF 経由 |
| 3 | 📊 VictoriaMetrics 稼働 | （mc-gateway 上で）`curl -s http://127.0.0.1:8428/health` | `OK` |
| 4 | 📡 gRPC-Web ルーティング | ブラウザ DevTools > Network で `/shared.MetricsService/GetMetrics` を確認 | `Content-Type: application/grpc-web+proto` で `200` |

---

## 📜 ライセンス

[MIT License](LICENSE)