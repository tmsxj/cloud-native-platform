#!/bin/bash
# ============================================
# 监控组件清理脚本
# 功能：删除 monitoring 命名空间所有 Pod，保留配置
# 用法：bash delete-monitoring.sh
# ============================================

set -e

# ---- 加载统一环境配置 ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../../部署工具/env.sh"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

NAMESPACE="${MONITORING_NS:-monitoring}"

echo "============================================"
echo " 监控组件清理工具"
echo " 命名空间: $NAMESPACE"
echo "============================================"
echo ""
echo "⚠️ 将执行以下操作:"
echo "  1. 缩容所有 Deployment/StatefulSet 到 0"
echo "  2. 删除 DaemonSet（node-exporter, promtail）"
echo "  3. 保留所有 ConfigMap/Secret/Service"
echo "  4. 保留 PVC（数据不丢失）"
echo ""

# 1. 缩容 Deployment 到 0（保留配置）
echo "[1/4] 缩容 Deployment..."
for deploy in $(kubectl get deployment -n $NAMESPACE -o name | sed 's|deployment.apps/||'); do
    kubectl scale deployment $deploy -n $NAMESPACE --replicas=0
    echo "  ✓ $deploy → 0 replicas"
done

# 2. 缩容 StatefulSet 到 0
echo ""
echo "[2/4] 缩容 StatefulSet..."
for sts in $(kubectl get statefulset -n $NAMESPACE -o name | sed 's|statefulset.apps/||'); do
    kubectl scale statefulset $sts -n $NAMESPACE --replicas=0
    echo "  ✓ $sts → 0 replicas"
done

# 3. 删除 DaemonSet
echo ""
echo "[3/4] 删除 DaemonSet..."
for ds in $(kubectl get daemonset -n $NAMESPACE -o name | sed 's|daemonset.apps/||'); do
    kubectl delete daemonset $ds -n $NAMESPACE --wait=false
    echo "  ✓ $ds deleted"
done

# 4. 等待 Pod 全部终止
echo ""
echo "[4/4] 等待 Pod 清理..."
kubectl wait --for=delete pod --all -n $NAMESPACE --timeout=120s 2>/dev/null || true

echo ""
echo "============================================"
echo " ✅ 清理完成"
echo "============================================"
echo ""
echo "当前 Pod 状态:"
kubectl get pod -n $NAMESPACE 2>/dev/null || echo "  (无 Pod)"
echo ""
echo "保留的资源（可恢复）:"
echo "  ConfigMap:   $(kubectl get configmap -n $NAMESPACE --no-headers 2>/dev/null | wc -l) 个"
echo "  Secret:      $(kubectl get secret -n $NAMESPACE --no-headers 2>/dev/null | wc -l) 个"
echo "  Service:     $(kubectl get service -n $NAMESPACE --no-headers 2>/dev/null | wc -l) 个"
echo "  PVC:         $(kubectl get pvc -n $NAMESPACE --no-headers 2>/dev/null | wc -l) 个"
echo ""
echo "🔁 恢复命令: bash restore-monitoring.sh"
