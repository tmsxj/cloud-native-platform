#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl -n monitoring get ingress monitoring-ingress -o yaml > /tmp/monitoring-ingress.yaml
echo "=== servicemonitors (all ns) ==="
kubectl get servicemonitor --all-namespaces 2>/dev/null | grep -iE 'sky|es' || echo "(no sky/es servicemonitor)"
echo "=== done, yaml lines: ==="
wc -l /tmp/monitoring-ingress.yaml
