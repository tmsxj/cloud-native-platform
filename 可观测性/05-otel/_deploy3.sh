#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "=== apply new otel-collector (exporter -> tempo) ==="
kubectl -n monitoring apply -f /tmp/otel_collector.yaml
kubectl -n monitoring rollout restart deployment/otel-collector
kubectl -n monitoring rollout status deployment/otel-collector --timeout=120s
echo "=== wait 20s for demo trace to flow into tempo ==="
sleep 20
echo "=== collector logs (tail 12) — should show otlp/tempo, no jaeger error ==="
kubectl -n monitoring logs -l app=otel-collector --tail=12 2>/dev/null
echo "=== minio bucket contents (proves S3 write) ==="
kubectl -n monitoring run mc-verify --rm -i --restart=Never --image=192.168.1.61/minio/mc:latest --command -- sh -c "mc alias set m http://minio.monitoring:9000 minioadmin minioadmin >/dev/null 2>&1; mc ls --recursive m/tempo 2>/dev/null | head -20; echo DONE" 2>/dev/null
echo "=== tempo search (recent traces) ==="
kubectl -n monitoring run tverify --rm -i --restart=Never --image=192.168.1.61/library/alpine:latest --command -- sh -c "apk add -q curl >/dev/null 2>&1; curl -s http://tempo.monitoring:3200/api/search; echo" 2>/dev/null
