output "workload_identity_provider" {
  description = "GitHub Secret (GCP_WIF_PROVIDER) に設定する WIF プロバイダー名"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "ci_service_account" {
  description = "GitHub Secret (GCP_SERVICE_ACCOUNT) に設定する CI SA メールアドレス"
  value       = google_service_account.tagomori_ci_sa.email
}
