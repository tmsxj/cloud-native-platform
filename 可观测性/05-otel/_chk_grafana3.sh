#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
NS=monitoring
echo "=== all enabled datasource plugin ids ==="
kubectl -n $NS get --raw '/api/v1/namespaces/monitoring/services/grafana:80/proxy/api/plugins?type=datasource&enabled=true' \
  | grep -oE '"id":"[^"]+"' | sort -u
echo "=== is tempo plugin bundled? (check installed plugins list) ==="
kubectl -n $NS get --raw '/api/v1/namespaces/monitoring/services/grafana:80/proxy/api/plugins?type=datasource' \
  | grep -oiE '"id":"(tempo|jaeger|zipkin|opentelemetry|grafana-opentracing)'
echo "=== end ==="
