#!/bin/bash
# P1.7: Prometheus ServiceMonitor 改造 — 完整部署脚本
set -e

echo "==============================================="
echo "P1.7 Phase 1: 拉取 operator 镜像 (h1 → Harbor)"
echo "==============================================="

# 从 quay.io 拉取 operator 和 config-reloader
echo ">>> Pulling prometheus-operator..."
sudo crictl pull quay.io/prometheus-operator/prometheus-operator:v0.78.2 2>&1 || {
  echo "v0.78.2 failed, trying v0.77.1..."
  sudo crictl pull quay.io/prometheus-operator/prometheus-operator:v0.77.1 2>&1
}

echo ">>> Pulling config-reloader..."
sudo crictl pull quay.io/prometheus-operator/prometheus-config-reloader:v0.78.2 2>&1 || {
  echo "v0.78.2 failed, trying v0.77.1..."
  sudo crictl pull quay.io/prometheus-operator/prometheus-config-reloader:v0.77.1 2>&1
}

echo ">>> Saving images to tar..."
sudo ctr -n k8s.io images export /tmp/operator.tar quay.io/prometheus-operator/prometheus-operator:v0.78.2 2>&1 || \
sudo ctr -n k8s.io images export /tmp/operator.tar quay.io/prometheus-operator/prometheus-operator:v0.77.1 2>&1

sudo ctr -n k8s.io images export /tmp/reloader.tar quay.io/prometheus-operator/prometheus-config-reloader:v0.78.2 2>&1 || \
sudo ctr -n k8s.io images export /tmp/reloader.tar quay.io/prometheus-operator/prometheus-config-reloader:v0.77.1 2>&1

ls -lh /tmp/operator.tar /tmp/reloader.tar
echo "Phase 1 done."
