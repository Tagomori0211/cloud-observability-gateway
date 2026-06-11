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
  description = "GCE A (sushiski-app) のマシンタイプ"
  type        = string
  default     = "e2-small"
}
