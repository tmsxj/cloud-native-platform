#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
NS=monitoring
for r in deploy sts ds svc cm secret ingress pvc hpa; do
  echo "== $r =="
  kubectl -n $NS get $r 2>/dev/null | grep -iE 'sky|elastic|es-' || echo "(none)"
done
echo "== ingress (all ns) =="
kubectl get ingress --all-namespaces 2>/dev/null | grep -iE 'sky|es|tracing|jaeger' || echo "(none)"
echo "== services in monitoring referencing 12800/30900/9200/5601 =="
kubectl -n $NS get svc -o wide 2>/dev/null
