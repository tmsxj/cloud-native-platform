#!/bin/bash
# P1.7 Phase 2: 修复 RBAC + 重新部署
set -e

echo "==============================================="
echo "P1.7 Phase 2: 修复权限 + 重启 Operator"
echo "==============================================="

# 1. 重新应用修复后的 YAMLs
echo ">>> 应用修复版 RBAC + Operator..."
echo 123 | sudo -S kubectl apply -f /tmp/p1.7-01.yaml 2>&1

# 2. 重启 operator 使新权限生效
echo ">>> 重启 Operator..."
echo 123 | sudo -S kubectl rollout restart deploy/prometheus-operator -n monitoring 2>&1
echo "  waiting for operator restart..."
for i in $(seq 1 15); do
  READY=$(echo 123 | sudo -S kubectl get pod -n monitoring -l app=prometheus-operator -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  if [ "$READY" = "True" ]; then echo "  Operator Ready!"; break; fi
  sleep 3
done

# 3. 删除旧 Prometheus CR 重新创建
echo ">>> 重新创建 Prometheus CR..."
echo 123 | sudo -S kubectl delete prometheus managed -n monitoring --ignore-not-found 2>&1
sleep 5
echo 123 | sudo -S kubectl apply -f /tmp/p1.7-02.yaml 2>&1

# 4. 等待 managed Prometheus pod
echo ">>> 等待 Prometheus Pod 创建..."
for i in $(seq 1 30); do
  POD=$(echo 123 | sudo -S kubectl get pod -n monitoring -l operated-prometheus=true -o name 2>/dev/null)
  if [ -n "$POD" ]; then
    echo "  Pod found: $POD"
    echo "  waiting for Ready..."
    echo 123 | sudo -S kubectl wait --for=condition=Ready pod -n monitoring -l operated-prometheus=true --timeout=120s 2>&1
    break
  fi
  sleep 5
  echo "  ... waiting ($i)"
done

# 5. 检查状态
echo ""
echo "==============================================="
echo ">>> 最终状态"
echo "==============================================="
echo 123 | sudo -S kubectl get prometheus managed -n monitoring 2>&1
echo ""
echo 123 | sudo -S kubectl get pod -n monitoring -l operated-prometheus=true 2>&1
echo ""
echo 123 | sudo -S kubectl get servicemonitor -n monitoring 2>&1
echo ""
echo 123 | sudo -S kubectl top nodes 2>&1 | grep worker
