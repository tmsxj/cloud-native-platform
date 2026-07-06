#!/bin/bash
# P1.7: Prometheus ServiceMonitor — 一键部署 (fixed sudo)
set -e
SP="echo 123 | sudo -S"

echo "==============================================="
echo "P1.7: Prometheus Operator + ServiceMonitor 部署"
echo "==============================================="

# Step 1: 给 Service 打 label
echo ">>> Step 1: 添加 Service labels..."
echo 123 | sudo -S kubectl label svc -n monitoring skywalking-oap app=skywalking component=oap --overwrite 2>&1
echo 123 | sudo -S kubectl label svc -n tomcat-prod tomcat-app app=tomcat-app --overwrite 2>&1

# Step 2: 部署 Operator
echo ">>> Step 2: 部署 Operator Controller..."
echo 123 | sudo -S kubectl apply -f /tmp/p1.7-01.yaml 2>&1

echo "  waiting for operator pod..."
for i in $(seq 1 20); do
  READY=$(echo 123 | sudo -S kubectl get pod -n monitoring -l app=prometheus-operator -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  if [ "$READY" = "True" ]; then echo "  Operator Ready!"; break; fi
  sleep 3
done

# Step 3: 部署 Prometheus CR
echo ">>> Step 3: 部署 Prometheus CR..."
echo 123 | sudo -S kubectl apply -f /tmp/p1.7-02.yaml 2>&1

echo "  waiting for managed Prometheus (may take ~60s)..."
for i in $(seq 1 40); do
  PHASE=$(echo 123 | sudo -S kubectl get prometheus managed -n monitoring -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
  if [ "$PHASE" = "True" ]; then echo "  Prometheus CR Ready!"; break; fi
  sleep 5
done

# Step 4: 部署 ServiceMonitors
echo ">>> Step 4: 部署 ServiceMonitors..."
echo 123 | sudo -S kubectl apply -f /tmp/p1.7-03.yaml 2>&1

# Step 5: 状态检查
echo ""
echo "==============================================="
echo ">>> 部署状态汇总"
echo "==============================================="
echo ""
echo "--- Operator Pod ---"
echo 123 | sudo -S kubectl get pod -n monitoring -l app=prometheus-operator 2>&1
echo ""
echo "--- Managed Prometheus ---"
echo 123 | sudo -S kubectl get prometheus -n monitoring managed 2>&1
echo ""
echo "--- ServiceMonitors ---"
echo 123 | sudo -S kubectl get servicemonitor -n monitoring 2>&1
echo ""
echo "--- Prometheus Pods ---"
echo 123 | sudo -S kubectl get pod -n monitoring -l operated-prometheus=true 2>&1
echo ""
echo "部署完成!"
