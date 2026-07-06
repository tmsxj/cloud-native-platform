#!/bin/bash
# P1.8: 部署 Loki LogQL 告警规则 (简化版)
set -e

echo "==============================================="
echo "P1.8: 日志分级告警 (Loki Ruler + Alertmanager)"
echo "==============================================="

# Step 1: Apply ConfigMap
echo ">>> Step 1: 创建 Loki rules ConfigMap..."
echo 123 | sudo -S kubectl apply -f /tmp/loki-rules-configmap.yaml 2>&1

# Step 2: Patch Loki StatefulSet
echo ">>> Step 2: Patch Loki StatefulSet..."
echo 123 | sudo -S kubectl patch sts loki -n monitoring --type=json -p '[
  {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"loki-rules","configMap":{"name":"loki-alert-rules"}}},
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"loki-rules","mountPath":"/var/loki/rules/fake","readOnly":true}}
]' 2>&1

# Step 3: 等待重启
echo ">>> Step 3: 等待 Loki 重启..."
sleep 10
echo 123 | sudo -S kubectl rollout status sts/loki -n monitoring --timeout=180s 2>&1

# Step 4: 验证
echo ">>> Step 4: 验证..."
LOKI_POD=$(echo 123 | sudo -S kubectl get pod -n monitoring loki-0 -o name 2>/dev/null)
echo "Loki Pod: ${LOKI_POD}"
echo 123 | sudo -S kubectl exec -n monitoring ${LOKI_POD} -- ls -la /var/loki/rules/fake/ 2>&1

echo ""
echo 123 | sudo -S kubectl logs -n monitoring ${LOKI_POD} --tail=20 2>&1 | grep -iE 'rule|ruler|alert|loaded' || echo "(no ruler logs yet, may need more time)"

echo ""
echo "==============================================="
echo ">>> P1.8 部署完成"
echo "==============================================="
echo "  告警规则: 3 条 (ERROR/Exception/OOM)"
echo "  发送目标: Alertmanager (http://alertmanager.monitoring:9093)"
