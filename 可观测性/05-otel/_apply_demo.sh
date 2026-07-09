#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
NS=monitoring
echo "=== delete old demo deployment + configmap ==="
kubectl -n $NS delete deployment otel-demo-app --ignore-not-found
kubectl -n $NS delete configmap otel-demo-app --ignore-not-found
echo "=== apply new demo app ==="
kubectl apply -f /tmp/otel-demo-app.yaml
sleep 5
echo "=== pod status ==="
kubectl -n $NS get pods -l app=otel-demo-app
sleep 20
echo "=== pod logs ==="
kubectl -n $NS logs -l app=otel-demo-app --tail=5
echo "=== Jaeger services ==="
kubectl -n $NS get --raw '/api/v1/namespaces/monitoring/services/jaeger:16686/proxy/api/services'
echo
