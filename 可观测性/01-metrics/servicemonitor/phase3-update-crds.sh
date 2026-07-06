#!/bin/bash
# P1.7 Phase 3: 从 GitHub 下载匹配的 CRD 并更新
set -e

echo "==============================================="
echo "P1.7 Phase 3: 更新 CRD Schema (匹配 v0.78.2)"
echo "==============================================="

CRD_URL="https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.78.2/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml"

# 下载最新 prometheuses CRD
echo ">>> 下载最新 CRD..."
curl -sL "$CRD_URL" -o /tmp/prometheuses-crd.yaml 2>&1
echo "CRD downloaded: $(wc -l < /tmp/prometheuses-crd.yaml) lines"

# 也下载其他可能需要的 CRD
for crd in servicemonitors podmonitors prometheusrules alertmanagers thanosrulers probes scrapeconfigs alertmanagerconfigs prometheusagents; do
  url="https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.78.2/example/prometheus-operator-crd/monitoring.coreos.com_${crd}.yaml"
  curl -sL "$url" -o "/tmp/${crd}-crd.yaml" 2>&1
  echo "  ${crd}: $(wc -l < /tmp/${crd}-crd.yaml) lines"
done

echo ">>> CRD 下载完成"
ls -la /tmp/*-crd.yaml
