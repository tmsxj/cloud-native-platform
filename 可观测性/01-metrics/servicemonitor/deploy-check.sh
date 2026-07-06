#!/bin/bash
set -e

echo "==============================================="
echo "P1.7: Prometheus ServiceMonitor 改造 — 部署检查"
echo "==============================================="

# 1. 检查 skywalking-oap svc labels
echo ""
echo ">>> skywalking-oap svc labels:"
sudo kubectl get svc -n monitoring skywalking-oap -o yaml | grep -A5 'labels:'

echo ""
echo ">>> kube-state-metrics port names:"
sudo kubectl get svc -n monitoring kube-state-metrics -o jsonpath='{range .spec.ports[*]}{.name}{" "}{end}'

echo ""
echo ">>> 检查 operator 镜像拉取能力:"
sudo crictl pull quay.io/prometheus-operator/prometheus-operator:v0.78.2 2>&1 || echo "quay.io blocked, try Harbor"
sudo crictl pull quay.io/prometheus-operator/prometheus-config-reloader:v0.78.2 2>&1 || echo "reloader blocked"

echo ""
echo ">>> 当前 worker 资源:"
sudo kubectl top nodes 2>&1 | grep worker
