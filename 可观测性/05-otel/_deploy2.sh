#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "=== restart otel-collector (point to tempo) ==="
kubectl -n monitoring rollout restart deployment/otel-collector
kubectl -n monitoring rollout status deployment/otel-collector --timeout=120s
echo "=== apply grafana datasources (Tempo) + restart grafana ==="
kubectl -n monitoring apply -f /tmp/otel_ds.yaml
kubectl -n monitoring rollout restart deployment/grafana
sleep 12
echo "=== delete jaeger (replaced by tempo) ==="
kubectl -n monitoring delete deployment/jaeger service/jaeger --ignore-not-found
echo "=== collector logs (tail 15) ==="
kubectl -n monitoring logs -l app=otel-collector --tail=15 2>/dev/null
echo "=== wait 10s for demo trace to flow ==="
sleep 10
echo "=== tempo search (recent traces) ==="
kubectl -n monitoring run tempo-verify --rm -i --restart=Never --image=192.168.1.61/library/alpine:latest --command -- sh -c "apk add -q curl >/dev/null 2>&1; curl -s http://tempo.monitoring:3200/api/search; echo" 2>/dev/null
echo "=== grafana datasources now ==="
kubectl -n monitoring get cm grafana-datasources -o yaml 2>/dev/null | grep -iE "name:|type:|url:"
echo "=== pods summary ==="
kubectl -n monitoring get pods | grep -iE "tempo|minio|otel|jaeger|grafana"
