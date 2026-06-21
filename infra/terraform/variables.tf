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
  description = "GCE A (tagomori-app) のマシンタイプ。CPU はほぼ idle のため e2-micro(1GB) に縮小。RAM 余裕は swap 2GB + api の mem_limit/JVM ヒープ上限で確保する。"
  type        = string
  default     = "e2-micro"
}

variable "github_repo" {
  description = "GitHub リポジトリ (owner/name 形式)。WIF の attribute_condition で使用。"
  type        = string
  default     = "Tagomori0211/cloud-observability-gateway"
}
