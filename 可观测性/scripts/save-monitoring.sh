#!/bin/bash
# ============================================
# 监控配置保存脚本
# 功能：导出 monitoring 命名空间所有资源 + Grafana Dashboard
# 用法：bash save-monitoring.sh
# ============================================

set -e

# ---- 加载统一环境配置 ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../../部署工具/env.sh"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

NAMESPACE="${MONITORING_NS:-monitoring}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-admin}"
BACKUP_DIR="$SCRIPT_DIR/backup-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"/{configmaps,secrets,services,deployments,statefulsets,daemonsets,ingress,pvc,grafana-dashboards}

echo "============================================"
echo " 监控配置保存工具"
echo " 备份目录: $BACKUP_DIR"
echo "============================================"

# 1. 导出所有 ConfigMap
echo ""
echo "[1/8] 导出 ConfigMap..."
for cm in $(kubectl get configmap -n $NAMESPACE -o name | sed 's|configmap/||'); do
    kubectl get configmap $cm -n $NAMESPACE -o yaml > "$BACKUP_DIR/configmaps/$cm.yaml"
    echo "  ✓ $cm"
done

# 2. 导出所有 Secret
echo ""
echo "[2/8] 导出 Secret..."
for secret in $(kubectl get secret -n $NAMESPACE -o name | sed 's|secret/||' | grep -v 'sh.helm.release'); do
    kubectl get secret $secret -n $NAMESPACE -o yaml > "$BACKUP_DIR/secrets/$secret.yaml"
    echo "  ✓ $secret"
done

# 3. 导出所有 Service
echo ""
echo "[3/8] 导出 Service..."
for svc in $(kubectl get service -n $NAMESPACE -o name | sed 's|service/||'); do
    kubectl get service $svc -n $NAMESPACE -o yaml > "$BACKUP_DIR/services/$svc.yaml"
    echo "  ✓ $svc"
done

# 4. 导出所有 Deployment
echo ""
echo "[4/8] 导出 Deployment..."
for deploy in $(kubectl get deployment -n $NAMESPACE -o name | sed 's|deployment.apps/||'); do
    kubectl get deployment $deploy -n $NAMESPACE -o yaml > "$BACKUP_DIR/deployments/$deploy.yaml"
    echo "  ✓ $deploy"
done

# 5. 导出所有 StatefulSet
echo ""
echo "[5/8] 导出 StatefulSet..."
for sts in $(kubectl get statefulset -n $NAMESPACE -o name | sed 's|statefulset.apps/||'); do
    kubectl get statefulset $sts -n $NAMESPACE -o yaml > "$BACKUP_DIR/statefulsets/$sts.yaml"
    echo "  ✓ $sts"
done

# 6. 导出所有 DaemonSet
echo ""
echo "[6/8] 导出 DaemonSet..."
for ds in $(kubectl get daemonset -n $NAMESPACE -o name | sed 's|daemonset.apps/||'); do
    kubectl get daemonset $ds -n $NAMESPACE -o yaml > "$BACKUP_DIR/daemonsets/$ds.yaml"
    echo "  ✓ $ds"
done

# 7. 导出 Ingress 和 PVC
echo ""
echo "[7/8] 导出 Ingress + PVC..."
kubectl get ingress -n $NAMESPACE -o yaml > "$BACKUP_DIR/ingress/all-ingress.yaml" 2>/dev/null || echo "  (无 Ingress)"
kubectl get pvc -n $NAMESPACE -o yaml > "$BACKUP_DIR/pvc/all-pvc.yaml"
echo "  ✓ Ingress + PVC"

# 8. 导出 Grafana Dashboard（通过 Grafana API）
echo ""
echo "[8/8] 导出 Grafana Dashboard..."
GRAFANA_POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
if [ -n "$GRAFANA_POD" ]; then
    # 获取 Dashboard 列表
    DASHBOARD_LIST=$(kubectl exec -n $NAMESPACE $GRAFANA_POD -- wget -q -O - http://${GRAFANA_USER}:${GRAFANA_PASS}@localhost:3000/api/search)
    
    # 导出每个 Dashboard 为 JSON
    echo "$DASHBOARD_LIST" | grep -o '"uid":"[^"]*"' | sed 's/"uid":"\([^"]*\)"/\1/' | while read uid; do
        kubectl exec -n $NAMESPACE $GRAFANA_POD -- wget -q -O - "http://${GRAFANA_USER}:${GRAFANA_PASS}@localhost:3000/api/dashboards/uid/$uid" \
            > "$BACKUP_DIR/grafana-dashboards/$uid.json"
        echo "  ✓ Dashboard: $uid"
    done
    
    # 导出数据源配置
    kubectl exec -n $NAMESPACE $GRAFANA_POD -- wget -q -O - http://${GRAFANA_USER}:${GRAFANA_PASS}@localhost:3000/api/datasources \
        > "$BACKUP_DIR/grafana-dashboards/datasources.json"
    echo "  ✓ Datasources"
fi

# 9. 也导出 Prometheus alerting_rules.yml（独立文件，方便查看）
echo ""
echo "[额外] 导出告警规则独立文件..."
kubectl get configmap prometheus-server -n $NAMESPACE -o jsonpath='{.data.alerting_rules\.yml}' \
    > "$BACKUP_DIR/prometheus-alerting-rules.yml" 2>/dev/null || true
kubectl get configmap alertmanager -n $NAMESPACE -o jsonpath='{.data.alertmanager\.yml}' \
    > "$BACKUP_DIR/alertmanager.yml" 2>/dev/null || true

echo ""
echo "============================================"
echo " ✅ 备份完成！"
echo " 备份目录: $BACKUP_DIR"
echo " 文件数: $(find $BACKUP_DIR -type f | wc -l)"
echo "============================================"
echo ""
echo "包含内容:"
echo "  - ConfigMap  : $(ls $BACKUP_DIR/configmaps/ 2>/dev/null | wc -l) 个"
echo "  - Secret     : $(ls $BACKUP_DIR/secrets/ 2>/dev/null | wc -l) 个"
echo "  - Service    : $(ls $BACKUP_DIR/services/ 2>/dev/null | wc -l) 个"
echo "  - Deployment : $(ls $BACKUP_DIR/deployments/ 2>/dev/null | wc -l) 个"
echo "  - StatefulSet: $(ls $BACKUP_DIR/statefulsets/ 2>/dev/null | wc -l) 个"
echo "  - DaemonSet  : $(ls $BACKUP_DIR/daemonsets/ 2>/dev/null | wc -l) 个"
echo "  - Dashboard  : $(ls $BACKUP_DIR/grafana-dashboards/ 2>/dev/null | wc -l) 个"
echo ""
echo "⚠️ 注意: PVC 数据（Prometheus TSDB、Grafana SQLite）未包含在纯 YAML 备份中"
echo "   如需完整迁移，请额外备份 PVC 底层存储"
