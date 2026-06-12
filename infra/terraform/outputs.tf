output "sushiski_app_external_ip" {
  description = "GCE A (sushiski-app) 外部 IP — IAP SSH の接続先ホスト名として使用"
  value       = google_compute_address.sushiski_app_ip.address
}

output "sushiski_app_internal_ip" {
  description = "GCE A (sushiski-app) VPC 内部 IP"
  value       = google_compute_instance.sushiski_app.network_interface[0].network_ip
}

output "workload_identity_provider" {
  description = "GitHub Secret (GCP_WIF_PROVIDER) に設定する WIF プロバイダー名"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "ci_service_account" {
  description = "GitHub Secret (GCP_SERVICE_ACCOUNT) に設定する CI SA メールアドレス"
  value       = google_service_account.sushiski_ci_sa.email
}

output "victoria_metrics_url" {
  description = "VICTORIA_METRICS_URL — VPC 内部 IP 直接通信 (.env / Ansible に設定する値)"
  value       = "http://${data.google_compute_instance.mc_monitoring.network_interface[0].network_ip}:8428"
}
