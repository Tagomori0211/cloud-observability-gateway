variable "project_id" {
  description = "GCP project ID（既存インフラと同一プロジェクト）"
  type        = string
}

variable "region" {
  description = "GCP region（既存インフラに合わせて tokyo）"
  type        = string
  default     = "asia-northeast1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "asia-northeast1-b"
}

variable "machine_type" {
  description = "GCE A (tagomori-app) のマシンタイプ"
  type        = string
  default     = "e2-small"
}

variable "github_repo" {
  description = "GitHub リポジトリ (owner/name 形式)。WIF の attribute_condition で使用。"
  type        = string
  default     = "Tagomori0211/cloud-observability-gateway"
}
