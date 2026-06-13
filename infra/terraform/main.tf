terraform {
  required_version = ">= 1.5.0"
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
# Data: 既存リソースの参照（作成しない）
# ============================================================
# 既存 tak-vpc / tak-subnet は Minecraft-on-Kubenates リポジトリの
# Terraform/main.tf が管理。ここでは data source として参照のみ。

data "google_compute_network" "tak_vpc" {
  name = "tak-vpc"
}

data "google_compute_subnetwork" "tak_subnet" {
  name   = "tak-vpc-subnet"
  region = var.region
}

# 既存 SA: mc-proxy-sa（Secret Manager 読取権限保有）
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
# 静的 IP: tagomori-app 用（SSH CI ターゲットとして利用）
# ============================================================
resource "google_compute_address" "tagomori_app_ip" {
  name   = "tagomori-app-ip"
  region = var.region
  labels = local.common_labels
}

# ============================================================
# Data: mc-monitoring-1 の内部 IP を取得（URL 生成用）
# ============================================================
data "google_compute_instance" "mc_monitoring" {
  name = "mc-monitoring-1"
  zone = var.zone
}

# ============================================================
# Firewall: IAP SSH — tagomori タグ
# ============================================================
# 既存の tak-vpc-allow-iap-ssh は "minecraft" タグのみ対象。
# tagomori-app は "tagomori" タグで分離し、独立して管理する。
resource "google_compute_firewall" "tagomori_iap_ssh" {
  name    = "tak-vpc-allow-iap-ssh-tagomori"
  network = data.google_compute_network.tak_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # GCP IAP のソース IP レンジ
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["tagomori"]

  description = "Allow SSH via IAP for tagomori-app"
}

# ============================================================
# GCE A: tagomori-app（新規作成）
# ============================================================
resource "google_compute_instance" "tagomori_app" {
  name         = "tagomori-app"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["tagomori", "tailscale"]

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2404-lts-amd64"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = data.google_compute_subnetwork.tak_subnet.name
    access_config {
      nat_ip = google_compute_address.tagomori_app_ip.address
    }
  }

  # 既存 mc-proxy-sa を流用（Secret Manager 読取権限保有済み）
  service_account {
    email  = data.google_service_account.mc_proxy_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    # CI SA は OS Login で SSH する（メタデータ SSH キーは setMetadata 権限が必要になるため不可）
    enable-oslogin = "TRUE"
    # Tailscale + Docker を初回プロビジョニング
    user-data = file("${path.module}/../cloud-init/tagomori-app.yaml")
  }

  shielded_instance_config {
    enable_secure_boot          = false
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  labels = local.common_labels

  lifecycle {
    ignore_changes = [metadata["ssh-keys"]]
  }
}

# ============================================================
# Secret Manager: tagomori-tunnel-token
# ============================================================
# skeleton のみ Terraform で作成。実際の値は Cloudflare Tunnel 作成後に手動で登録:
#   gcloud secrets versions add tagomori-tunnel-token --data-file=- <<< "eyJ..."
# ============================================================
# Firewall: tagomori-app → mc-monitoring-1 (VictoriaMetrics :8428)
# ============================================================
# mc-monitoring-1 は "minecraft" タグを持つ。
# tagomori-app ("tagomori" タグ) から VPC 内部で :8428 に到達できるようにする。
# VictoriaMetrics は 0.0.0.0:8428 でバインド済み（gce/monitoring/compose.yaml）。
resource "google_compute_firewall" "allow_vm_8428_from_tagomori" {
  name    = "tak-vpc-allow-vm-8428-from-tagomori"
  network = data.google_compute_network.tak_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8428"]
  }

  source_tags = ["tagomori"]   # FROM tagomori-app
  target_tags = ["minecraft"]  # TO mc-monitoring-1 (既存タグ)

  description = "Allow tagomori-app to reach VictoriaMetrics on mc-monitoring-1 via VPC"
}

# ============================================================
# Secret Manager: tagomori-tunnel-token
# ============================================================
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
