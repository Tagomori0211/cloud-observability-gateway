terraform {
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  # State は既存インフラとは独立。GCS バックエンド推奨（初回のみ手動作成）。
  # backend "gcs" {
  #   bucket = "tak-pipeline-tfstate"
  #   prefix = "tagomori-status/state"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ============================================================
# 実行環境（2026-09-30〜）
# ============================================================
# Status Platform は Minecraft-on-Kubernetes リポジトリが管理する統合 VM mc-gateway
# （Terraform/gateway.tf、SA: mc-proxy-sa）上で動く。本リポジトリの Terraform は
# VM を持たず、CI デプロイ用の SA / WIF と Secret のみを管理する。
# 旧 tagomori-app VM・静的 IP・専用 Firewall は統合に伴い削除した。

# 既存 SA: mc-proxy-sa（mc-gateway の VM SA。CI が actAs して SSH デプロイする）
data "google_service_account" "mc_proxy_sa" {
  account_id = "mc-proxy-sa"
}

# ============================================================
# Locals: 既存インフラと統一したラベル
# ============================================================
locals {
  common_labels = {
    "app-part-of" = "tak-pipeline"
    "environment" = "prod"
    "managed-by"  = "terraform"
    "component"   = "tagomori-status"
  }
}

# ============================================================
# Secret Manager: tagomori-tunnel-token
# ============================================================
# skeleton のみ Terraform で作成。実際の値は Cloudflare Tunnel 作成後に手動で登録:
#   gcloud secrets versions add tagomori-tunnel-token --data-file=- <<< "eyJ..."
resource "google_secret_manager_secret" "tagomori_tunnel_token" {
  secret_id = "tagomori-tunnel-token"
  replication {
    auto {}
  }
  labels = local.common_labels
}

# ============================================================
# CI 用 Service Account（GitHub Actions → IAP SSH + Artifact 操作）
# ============================================================
resource "google_service_account" "tagomori_ci_sa" {
  account_id   = "tagomori-ci-sa"
  display_name = "Sushiski Status CI/CD Service Account"
  description  = "Used by GitHub Actions to deploy via IAP SSH."
}

# IAP トンネル接続権限（gcloud compute ssh --tunnel-through-iap）
resource "google_project_iam_member" "ci_iap_tunnel" {
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:${google_service_account.tagomori_ci_sa.email}"
}

# IAP 経由の OS Login
resource "google_project_iam_member" "ci_os_login" {
  project = var.project_id
  role    = "roles/compute.osLogin"
  member  = "serviceAccount:${google_service_account.tagomori_ci_sa.email}"
}

# Compute 読取（インスタンス名解決に必要）
resource "google_project_iam_member" "ci_compute_viewer" {
  project = var.project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.tagomori_ci_sa.email}"
}

# VM が mc-proxy-sa を使用しているため、SSH には actAs 権限が必要
resource "google_service_account_iam_member" "ci_act_as_vm_sa" {
  service_account_id = data.google_service_account.mc_proxy_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.tagomori_ci_sa.email}"
}

# ============================================================
# Workload Identity Federation (GitHub Actions → GCP, キーレス認証)
# ============================================================
# 組織ポリシー constraints/iam.disableServiceAccountKeyCreation により
# SA キー作成が禁止されているため WIF を使用する。
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions Pool"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Actions Provider"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.actor"      = "assertion.actor"
    "attribute.aud"        = "assertion.aud"
  }

  attribute_condition = "assertion.repository == \"${var.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_wif" {
  service_account_id = google_service_account.tagomori_ci_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}
