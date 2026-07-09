#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
NS=monitoring
echo "=== monitoring 关键 Pod ==="
kubectl -n $NS get pods -l 'app in (jaeger,otel-collector,otel-demo-app)' -o wide
echo "=== 残留 skywalking/es? ==="
kubectl -n $NS get all | grep -iE 'sky|elasticsearch' || echo "(无残留)"
echo "=== Jaeger services ==="
kubectl -n $NS get --raw '/api/v1/namespaces/monitoring/services/jaeger:16686/proxy/api/services'
echo
