#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
NS=monitoring
echo "=== grafana version ==="
kubectl -n $NS get --raw '/api/v1/namespaces/monitoring/services/grafana:80/proxy/api/health'
echo
echo "=== enabled datasource plugins (id/name/type) ==="
kubectl -n $NS get --raw '/api/v1/namespaces/monitoring/services/grafana:80/proxy/api/plugins?type=datasource&enabled=true' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); [print(p['id'], '|', p.get('name'), '|', p.get('type')) for p in d if any(t in p['id'] for t in ['jaeger','tempo','zipkin','loki','prometheus','opentelemetry'])]" 2>/dev/null || \
kubectl -n $NS get --raw '/api/v1/namespaces/monitoring/services/grafana:80/proxy/api/plugins?type=datasource&enabled=true'
