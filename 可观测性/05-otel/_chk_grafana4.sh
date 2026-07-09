#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
NS=monitoring
POD=$(kubectl -n $NS get pod -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
echo "pod=$POD"
echo "=== datasource plugin ids via localhost ==="
kubectl -n $NS exec "$POD" -- sh -c 'wget -qO- "http://localhost:3000/api/plugins?type=datasource" 2>/dev/null | grep -oE "\"id\":\"[^\"]+\"" | sort -u' || \
kubectl -n $NS exec "$POD" -- sh -c 'curl -s "http://localhost:3000/api/plugins?type=datasource" 2>/dev/null | grep -oE "\"id\":\"[^\"]+\"" | sort -u'
echo "=== end ==="
