#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
NS=monitoring
echo "=== grafana health ==="
kubectl -n $NS get --raw '/api/v1/namespaces/monitoring/services/grafana:80/proxy/api/health'; echo
echo "=== datasource plugins (jaeger/tempo) ==="
kubectl -n $NS get --raw '/api/v1/namespaces/monitoring/services/grafana:80/proxy/api/plugins?type=datasource&enabled=true' \
  | grep -oiE '"(id|name|type)":"[^"]*(jaeger|tempo|zipkin|opentelemetry)[^"]*"' | head -40
echo "=== end ==="
