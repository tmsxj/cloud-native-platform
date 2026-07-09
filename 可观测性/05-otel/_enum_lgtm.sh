#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "=== pods (monitoring) ==="
kubectl -n monitoring get pods -o wide
echo ""
echo "=== cm list (monitoring) ==="
kubectl -n monitoring get cm
echo ""
echo "=== pvc (monitoring) ==="
kubectl -n monitoring get pvc 2>/dev/null
echo ""
echo "=== storageclass ==="
kubectl get sc
echo ""
echo "=== tempo/minio already exist? ==="
kubectl -n monitoring get deploy,sts,svc 2>/dev/null | grep -iE "tempo|minio" || echo "NONE"
echo ""
echo "=== loki config (storage backend) ==="
kubectl -n monitoring get cm loki-config -o yaml 2>/dev/null | grep -iE "backend|s3|bucket|endpoint|minio|filesystem" || echo "no loki-config cm"
echo ""
echo "=== otel-collector exporters ==="
kubectl -n monitoring get cm otel-collector -o yaml 2>/dev/null | grep -iE "exporters|jaeger|tempo|endpoint|otlp" || echo "no otel-collector cm"
echo ""
echo "=== grafana datasources ==="
kubectl -n monitoring get cm grafana-datasources -o yaml 2>/dev/null | grep -iE "type:|url:|jaeger|tempo|prometheus|loki" || echo "no grafana-datasources cm"
