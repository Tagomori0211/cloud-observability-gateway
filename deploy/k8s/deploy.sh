#!/usr/bin/env bash
# k3s-worker 上で実行する。/opt/tagomori-status/releases/<sha> に展開済みのリリースを適用する。
# 使い方: sudo deploy.sh <sha>
set -euo pipefail

SHA="$1"
ROOT=/opt/tagomori-status/releases
REL="$ROOT/$SHA"
NS=tagomori-status
K="kubectl -n $NS"

test -f "$REL/app.jar" && test -d "$REL/web"

kubectl apply -f "$REL/k8s/namespace.yaml"

# Secret は CI が事前に作成する（ここでは存在確認のみ）
for s in tagomori-status-db cloudflared-token gcp-credentials; do
  $K get secret "$s" >/dev/null
done

$K create configmap envoy-config --from-file=envoy.yaml="$REL/envoy.yaml" \
  --dry-run=client -o yaml | kubectl apply -f -

HASH=$(sha256sum "$REL/envoy.yaml" | cut -c1-16)
kubectl apply -f "$REL/k8s/mariadb.yaml"
sed "s/__RELEASE__/$SHA/" "$REL/k8s/api.yaml" | kubectl apply -f -
sed "s/__ENVOY_HASH__/$HASH/" "$REL/k8s/envoy.yaml" | kubectl apply -f -
kubectl apply -f "$REL/k8s/cloudflared.yaml"

$K rollout status statefulset/mariadb --timeout=180s
$K rollout status deployment/api --timeout=300s
$K rollout status deployment/envoy --timeout=120s
$K rollout status deployment/cloudflared --timeout=120s

# 直近 5 リリースだけ残す（稼働中のものは消さない）
ls -1t "$ROOT" | tail -n +6 | { grep -vx "$SHA" || true; } | while read -r old; do rm -rf "${ROOT:?}/$old"; done
