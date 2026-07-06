#!/bin/bash
# ============================================
# 监控组件恢复脚本
# 功能：从备份文件恢复所有 monitoring 组件
# 用法：bash restore-monitoring.sh [备份目录路径]
# ============================================

set -e

# ---- 加载统一环境配置 ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../../部署工具/env.sh"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

NAMESPACE="${MONITORING_NS:-monitoring}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-admin}"

# 查找最新的备份目录
if [ -n "$1" ]; then
    BACKUP_DIR="$1"
else
    BACKUP_DIR=$(ls -dt "$(dirname "$0")"/backup-* 2>/dev/null | head -1)
fi

if [ -z "$BACKUP_DIR" ] || [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ 未找到备份目录"
    echo "用法: bash restore-monitoring.sh <备份目录>"
    exit 1
fi

echo "============================================"
echo " 监控组件恢复工具"
echo " 备份目录: $BACKUP_DIR"
echo "============================================"

# 1. 恢复 ConfigMap（先恢复，因为 Deployment 依赖它）
echo ""
echo "[1/7] 恢复 ConfigMap..."
if [ -d "$BACKUP_DIR/configmaps" ] && [ "$(ls -A $BACKUP_DIR/configmaps 2>/dev/null)" ]; then
    for f in "$BACKUP_DIR/configmaps"/*.yaml; do
        # 清除 resourceVersion 等集群特定字段
        kubectl apply -f "$f" 2>/dev/null || true
        echo "  ✓ $(basename $f .yaml)"
    done
else
    echo "  (无 ConfigMap)"
fi

# 2. 恢复 Secret
echo ""
echo "[2/7] 恢复 Secret..."
if [ -d "$BACKUP_DIR/secrets" ] && [ "$(ls -A $BACKUP_DIR/secrets 2>/dev/null)" ]; then
    for f in "$BACKUP_DIR/secrets"/*.yaml; do
        kubectl apply -f "$f" 2>/dev/null || true
        echo "  ✓ $(basename $f .yaml)"
    done
fi

# 3. 恢复 Service
echo ""
echo "[3/7] 恢复 Service..."
if [ -d "$BACKUP_DIR/services" ] && [ "$(ls -A $BACKUP_DIR/services 2>/dev/null)" ]; then
    for f in "$BACKUP_DIR/services"/*.yaml; do
        kubectl apply -f "$f" 2>/dev/null || true
        echo "  ✓ $(basename $f .yaml)"
    done
fi

# 4. 恢复 DaemonSet
echo ""
echo "[4/7] 恢复 DaemonSet..."
if [ -d "$BACKUP_DIR/daemonsets" ] && [ "$(ls -A $BACKUP_DIR/daemonsets 2>/dev/null)" ]; then
    for f in "$BACKUP_DIR/daemonsets"/*.yaml; do
        kubectl apply -f "$f" 2>/dev/null || true
        echo "  ✓ $(basename $f .yaml)"
    done
fi

# 5. 恢复 StatefulSet
echo ""
echo "[5/7] 恢复 StatefulSet..."
if [ -d "$BACKUP_DIR/statefulsets" ] && [ "$(ls -A $BACKUP_DIR/statefulsets 2>/dev/null)" ]; then
    for f in "$BACKUP_DIR/statefulsets"/*.yaml; do
        kubectl apply -f "$f" 2>/dev/null || true
        echo "  ✓ $(basename $f .yaml)"
    done
fi

# 6. 恢复 Deployment（先 scale 到 1）
echo ""
echo "[6/7] 恢复 Deployment..."
if [ -d "$BACKUP_DIR/deployments" ] && [ "$(ls -A $BACKUP_DIR/deployments 2>/dev/null)" ]; then
    for f in "$BACKUP_DIR/deployments"/*.yaml; do
        kubectl apply -f "$f" 2>/dev/null || true
        deploy_name=$(basename $f .yaml)
        echo "  ✓ $deploy_name"
    done
fi

# 7. 等待 Pod 就绪
echo ""
echo "[7/7] 等待 Pod 就绪..."
sleep 5
echo "当前 Pod 状态:"
kubectl get pod -n $NAMESPACE

echo ""
echo "============================================"
echo " ✅ 恢复完成"
echo "============================================"
echo ""
echo "访问地址 (通过 Ingress):"
echo "  Grafana:     http://grafana.lab.local"
echo "  Prometheus:  http://prometheus.lab.local"
echo "  SkyWalking:  http://skywalking.lab.local"
echo ""
echo "⚠️ 如果 Grafana Dashboard 没恢复，通过 API 导入:"
echo "  for f in $BACKUP_DIR/grafana-dashboards/*.json; do"
echo "    cat \$f | curl -X POST http://${GRAFANA_USER}:${GRAFANA_PASS}@grafana.lab.local/api/dashboards/db \\"
echo "      -H 'Content-Type: application/json' -d @-"
echo "  done"
