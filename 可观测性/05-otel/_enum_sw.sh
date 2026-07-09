#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "=== namespaces ==="
kubectl get ns
echo "=== deployments (all ns) matching skywalking/es/elastic ==="
kubectl get deploy --all-namespaces | grep -iE 'sky|es-|elastic|elasticsearch' || echo "(none in deploy)"
echo "=== statefulsets (all ns) matching es/elastic ==="
kubectl get sts --all-namespaces | grep -iE 'es-|elastic|sky' || echo "(none in sts)"
echo "=== helm releases ==="
helm ls --all-namespaces 2>/dev/null || echo "(helm not found)"
echo "=== pods in monitoring with sky/es ==="
kubectl -n monitoring get pods 2>/dev/null | grep -iE 'sky|es|elastic' || echo "(none in monitoring)"
echo "=== all monitoring workloads ==="
kubectl -n monitoring get all 2>/dev/null
