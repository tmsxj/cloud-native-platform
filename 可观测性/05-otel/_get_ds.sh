#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl -n monitoring get cm grafana-datasources -o yaml > /tmp/grafana-datasources.yaml
echo "lines:"; wc -l /tmp/grafana-datasources.yaml
