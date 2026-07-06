#!/bin/bash
# P1.7 前置验证 - 检查现有 Service labels 和 ports
echo "=== kube-state-metrics svc labels ==="
sudo kubectl get svc -n monitoring kube-state-metrics -o jsonpath='{.metadata.labels}' 2>&1
echo ""
echo "=== node-exporter svc labels ==="
sudo kubectl get svc -n monitoring -l app.kubernetes.io/name=prometheus-node-exporter -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels}{"\n"}{end}' 2>&1
echo ""
echo "=== skywalking-oap svc labels ==="
sudo kubectl get svc -n monitoring skywalking-oap -o jsonpath='{.metadata.labels}' 2>&1
echo ""
echo "=== tomcat-prod svc labels ==="
sudo kubectl get svc -n tomcat-prod -o jsonpath='{range .items[*]}{.metadata.name}{"="}{.metadata.labels}{"\n"}{end}' 2>&1
echo ""
echo "=== kube-state-metrics svc ports ==="
sudo kubectl get svc -n monitoring kube-state-metrics -o jsonpath='{range .spec.ports[*]}{.name}{":"}{.port}{"\n"}{end}' 2>&1
echo ""
echo "=== node-exporter svc ==="
sudo kubectl get svc -n monitoring -l app.kubernetes.io/name=prometheus-node-exporter 2>&1
echo ""
echo "=== All CRDs related ==="
sudo kubectl get crd | grep monitoring.coreos.com 2>&1
echo ""
echo "=== Worker node capacity ==="
sudo kubectl top nodes | grep worker 2>&1
