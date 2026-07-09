#!/bin/bash
# 在 chaos-testing 命名空间部署 Chaos Mesh（worker 限定版）
# 用法: 在 m1 上 source 环境变量后执行  bash deploy.sh
set -e
export KUBECONFIG=/etc/kubernetes/admin.conf
NS=chaos-testing

helm repo add chaos-mesh https://charts.chaos-mesh.org 2>/dev/null || true
helm repo update

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
  -n "$NS" -f values-worker-scoped.yaml \
  --version 2.6.3 --wait --timeout 300s

echo "=== pods ==="
kubectl -n "$NS" get pods
echo "=== 验证 CRD ==="
kubectl get crd | grep chaos-mesh
echo "部署完成。Web UI: kubectl -n $NS port-forward svc/chaos-dashboard 2333:2333"
