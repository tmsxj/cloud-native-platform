#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
NS=monitoring
echo "=== apply grafana-datasources CM ==="
kubectl -n $NS apply -f /tmp/grafana-datasources.yaml
echo "=== restart grafana to re-provision ==="
kubectl -n $NS rollout restart deployment/grafana
kubectl -n $NS rollout status deployment/grafana --timeout=120s
sleep 8
echo "=== verify datasources via API ==="
kubectl -n $NS run dscheck --rm -i --restart=Never --image=192.168.1.61/library/alpine_curl -- sh -c \
  'curl -s -u admin:admin http://grafana.monitoring:80/api/datasources | grep -oE "\"name\":\"[^\"]+\"|\"type\":\"[^\"]+\""' 2>/dev/null
