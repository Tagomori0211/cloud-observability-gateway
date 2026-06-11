output "sushiski_app_external_ip" {
  description = "GCE A (sushiski-app) 外部 IP — IAP SSH の接続先ホスト名として使用"
  value       = google_compute_address.sushiski_app_ip.address
}

output "sushiski_app_internal_ip" {
  description = "GCE A (sushiski-app) VPC 内部 IP"
  value       = google_compute_instance.sushiski_app.network_interface[0].network_ip
}

output "ci_sa_key_b64" {
  description = "GitHub Secret (GCP_CI_SA_KEY) に設定する CI SA キー (base64)"
  value       = google_service_account_key.sushiski_ci_sa_key.private_key
  sensitive   = true
}

output "victoria_metrics_url" {
  description = "VICTORIA_METRICS_URL — VPC 内部 IP 直接通信 (.env / Ansible に設定する値)"
  value       = "http://${data.google_compute_instance.mc_monitoring.network_interface[0].network_ip}:8428"
}
