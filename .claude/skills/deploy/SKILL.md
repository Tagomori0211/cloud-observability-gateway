# k3s-worker へのデプロイ
1. 現在稼働中のリリースを確認（`ssh k3s-worker 'sudo kubectl -n tagomori-status get deploy api -o jsonpath="{.spec.template.spec.volumes[0].hostPath.path}"'`）
2. deploy.yml に必要なシークレット（DB_PASSWORD / K3S_SSH_KEY / K3S_KNOWN_HOSTS）が登録されているか確認（`gh secret list`）
3. namespace tagomori-status に手動 Secret（cloudflared-token / gcp-credentials）があるか、ランナーツール（rsync/jq/unzip）が入っているか確認
4. コミット・プッシュ・CI実行・実行確認（`gh run watch`）
5. 同期状態確認（Pod 状態・https://app.tagomori.dev/ の応答）
