#!/bin/bash
# 在 m1(控制面) 上执行：部署 Falco（离线适配版）
# 前置：falco chart 已置于 /tmp/falco-chart/falco（含 charts/ 依赖），覆盖值在 /tmp/falco-values.yaml
set -e
export KUBECONFIG=/etc/kubernetes/admin.conf

echo ">>> 创建命名空间 falco"
kubectl create namespace falco --dry-run=client -o yaml | kubectl apply -f -

echo ">>> helm install falco（modern_ebpf / Harbor 镜像 / 仅 worker）"
helm install falco /tmp/falco-chart/falco \
  -n falco \
  -f /tmp/falco-values.yaml \
  --wait --timeout 240s

echo ">>> 部署完成"
kubectl -n falco get ds,pods -o wide
