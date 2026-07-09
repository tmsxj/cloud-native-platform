#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
NS=monitoring
echo "=== live CM grafana-datasources (datasources.yaml) ==="
kubectl -n $NS get cm grafana-datasources -o yaml | sed -n '/datasources.yaml:/,/^kind:/p'
echo "=== grafana pod logs (provisioning / jaeger) ==="
kubectl -n $NS logs deploy/grafana --tail=40 | grep -iE 'provision|jaeger|datasource|error|fail' || echo "(no matching log lines)"
echo "=== re-query datasources ==="
kubectl -n $NS run dscheck2 --rm -i --restart=Never --image=192.168.1.61/library/alpine_curl -- sh -c \
  'curl -s -u admin:admin http://grafana.monitoring:80/api/datasources | grep -oE "\"name\":\"[^\"]+\""' 2>/dev/null
