#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "=== NODE STATUS ==="
kubectl get node -o wide
echo "=== kube-system pods ==="
kubectl get pods -n kube-system -o wide
echo "=== Cilium ==="
kubectl get pods -n kube-system -l k8s-app=cilium -o wide
echo "=== Falco ==="
kubectl get pods -n falco -o wide 2>/dev/null
echo "=== Kyverno ==="
kubectl get pods -n kyverno -o wide 2>/dev/null
echo "=== Linkerd ==="
kubectl get pods -n linkerd -o wide 2>/dev/null
echo "=== Istio-system ==="
kubectl get pods -n istio-system -o wide 2>/dev/null
