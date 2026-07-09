#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "=== apply minio ==="
kubectl -n monitoring apply -f /tmp/otel_minio.yaml
echo "=== apply tempo ==="
kubectl -n monitoring apply -f /tmp/otel_tempo.yaml
echo "=== wait tempo ready (max 150s) ==="
for i in $(seq 1 30); do
  rd=$(kubectl -n monitoring get pod -l app=tempo -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
  ph=$(kubectl -n monitoring get pod -l app=tempo -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
  echo "try $i: phase=$ph ready=$rd"
  if [ "$rd" = "true" ]; then echo "TEMPO_READY"; break; fi
  sleep 5
done
echo "=== tempo describe (events) ==="
kubectl -n monitoring describe pod -l app=tempo 2>/dev/null | sed -n '/Events:/,$p'
echo "=== tempo logs (tail 50) ==="
kubectl -n monitoring logs -l app=tempo --tail=50 2>/dev/null
echo "=== minio pod ==="
kubectl -n monitoring get pod -l app=minio
