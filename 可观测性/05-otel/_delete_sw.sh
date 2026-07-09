#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
NS=monitoring
echo "=== apply cleaned ingress (drop skywalking host) ==="
kubectl apply -f /tmp/monitoring-ingress-clean.yaml
echo "=== delete skywalking deployments ==="
kubectl -n $NS delete deploy skywalking-oap skywalking-ui --ignore-not-found
echo "=== delete elasticsearch statefulset ==="
kubectl -n $NS delete sts elasticsearch --ignore-not-found
echo "=== delete skywalking/es services ==="
kubectl -n $NS delete svc elasticsearch elasticsearch-headless skywalking-oap skywalking-ui --ignore-not-found
echo "=== delete elasticsearch PVCs (free local-path storage) ==="
kubectl -n $NS delete pvc data-elasticsearch-0 data-elasticsearch-1 data-elasticsearch-2 --ignore-not-found
echo "=== delete skywalking servicemonitor ==="
kubectl -n $NS delete servicemonitor skywalking-oap --ignore-not-found
echo "=== final monitoring workloads ==="
kubectl -n $NS get deploy,sts,svc,pvc
