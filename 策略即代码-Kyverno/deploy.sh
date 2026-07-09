#!/bin/bash
# 部署 Kyverno（worker 限定）+ 落地策略
# 用法: 在 m1 上 cd 本目录后 bash deploy.sh
set -e
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "===== [1/5] 加 helm repo ====="
helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
helm repo update kyverno

echo "===== [2/5] 建命名空间 + 给 worker 打标签 ====="
kubectl create namespace kyverno 2>/dev/null || true
kubectl label node worker1 worker2 kyverno-scope=true --overwrite

echo "===== [3/5] helm 安装 Kyverno (chart 3.8.1) ====="
helm upgrade --install kyverno kyverno/kyverno \
  -n kyverno -f values-worker-scoped.yaml --version 3.8.1

echo "===== [4/5] 等待 Pod Ready ====="
kubectl -n kyverno rollout status deploy/kyverno-admission-controller --timeout=180s
kubectl -n kyverno rollout status deploy/kyverno-background-controller --timeout=180s
echo "--- Kyverno Pod 分布（应全在 worker）---"
kubectl -n kyverno get pods -o wide

echo "===== [5/5] 落地策略 ====="
kubectl apply -f policies/
echo "--- 已生效策略 ---"
kubectl get clusterpolicy
echo "部署完成 ✅"
