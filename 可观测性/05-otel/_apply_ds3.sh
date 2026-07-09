#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
NS=monitoring
SRC=/tmp/otel_ds.yaml
echo "=== $SRC contains jaeger? ==="
grep -c jaeger $SRC
echo "=== apply ==="
kubectl -n $NS apply -f $SRC
echo "=== live CM now contains jaeger? ==="
kubectl -n $NS get cm grafana-datasources -o yaml | grep -c jaeger
echo "=== restart grafana ==="
kubectl -n $NS rollout restart deployment/grafana
kubectl -n $NS rollout status deployment/grafana --timeout=120s
sleep 10
echo "=== datasources after restart ==="
kubectl -n $NS run dscheck4 --rm -i --restart=Never --image=192.168.1.61/library/alpine_curl -- sh -c \
  'curl -s -u admin:admin http://grafana.monitoring:80/api/datasources | grep -oE "\"name\":\"[^\"]+\""' 2>/dev/null
