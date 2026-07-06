#!/bin/bash
# P1.8: 日志分级告警 — 通过 Grafana API 创建 Loki LogQL 告警规则
# 零额外资源消耗，直接使用现有 Grafana + Loki

GRAFANA="http://grafana.monitoring:3000"
USER="admin"
PASS="admin"

echo "==============================================="
echo "P1.8: 创建 Loki LogQL 告警规则"
echo "==============================================="

# 创建告警通知策略 (发送到现有 Alertmanager)
echo ">>> Step 1: 配置 Alertmanager 通知通道..."
# 先检查是否有现有通知通道
NOTIFIERS=$(curl -s -u ${USER}:${PASS} "${GRAFANA}/api/v1/provisioning/alert-notifications" 2>&1)
echo "Existing notifiers: $NOTIFIERS" | head -c 500

# 获取 Alertmanager UID
AM_UID=$(echo "$NOTIFIERS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0].get('uid','')) if d else print('none')" 2>/dev/null)
echo "Alertmanager UID: $AM_UID"

# 如果没有 Alertmanager notifier，创建一个
if [ "$AM_UID" = "none" ] || [ -z "$AM_UID" ]; then
  echo "Creating Alertmanager contact point..."
  curl -s -u ${USER}:${PASS} -X POST "${GRAFANA}/api/v1/provisioning/contact-points" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "alertmanager-default",
      "type": "prometheus-alertmanager",
      "settings": {
        "url": "http://alertmanager.monitoring:9093",
        "basicAuthUser": "",
        "basicAuthPassword": ""
      }
    }' 2>&1 | head -c 300
fi

echo ""
echo ">>> Step 2: 创建 ERROR 日志频率告警..."
# Rule 1: ERROR 日志频率超阈值 (tomcat 命名空间)
curl -s -u ${USER}:${PASS} -X POST "${GRAFANA}/api/v1/provisioning/alert-rules" \
  -H "Content-Type: application/json" \
  -H "X-Disable-Provenance: true" \
  -d '{
    "title": "Tomcat ERROR 日志频率告警",
    "ruleGroup": "log-alerts",
    "folderUID": "",
    "for": "5m",
    "orgID": 1,
    "condition": "C",
    "data": [
      {
        "refId": "A",
        "queryType": "range",
        "relativeTimeRange": { "from": 600, "to": 0 },
        "datasourceUid": "loki",
        "model": {
          "editorMode": "code",
          "expr": "sum(rate({namespace=\"tomcat-prod\"} |= \"ERROR\" [5m]))",
          "intervalMs": 60000,
          "maxDataPoints": 43200,
          "refId": "A"
        }
      },
      {
        "refId": "C",
        "queryType": "",
        "relativeTimeRange": { "from": 0, "to": 0 },
        "datasourceUid": "-100",
        "model": {
          "type": "math",
          "expression": "$A > 0.01"
        }
      }
    ],
    "noDataState": "NoData",
    "execErrState": "Error",
    "annotations": {
      "summary": "命名空间 tomcat-prod ERROR 日志频率超阈值",
      "description": "过去5分钟内 ERROR 日志速率为 {{ $values.A.Value }} 条/秒，超过 0.01 条/秒阈值"
    },
    "labels": {
      "severity": "warning",
      "source": "loki-logql"
    }
  }' 2>&1 | head -c 500

echo ""
echo ">>> Step 3: 创建 Java Exception 告警..."
# Rule 2: Java Exception 模式检测
curl -s -u ${USER}:${PASS} -X POST "${GRAFANA}/api/v1/provisioning/alert-rules" \
  -H "Content-Type: application/json" \
  -H "X-Disable-Provenance: true" \
  -d '{
    "title": "Java Exception 触发告警",
    "ruleGroup": "log-alerts",
    "folderUID": "",
    "for": "5m",
    "orgID": 1,
    "condition": "C",
    "data": [
      {
        "refId": "A",
        "queryType": "range",
        "relativeTimeRange": { "from": 600, "to": 0 },
        "datasourceUid": "loki",
        "model": {
          "editorMode": "code",
          "expr": "sum(count_over_time({namespace=~\"tomcat-.*\"} |~ \"(?i)(Exception|Error|FATAL)\" [5m]))",
          "intervalMs": 60000,
          "maxDataPoints": 43200,
          "refId": "A"
        }
      },
      {
        "refId": "C",
        "queryType": "",
        "relativeTimeRange": { "from": 0, "to": 0 },
        "datasourceUid": "-100",
        "model": {
          "type": "math",
          "expression": "$A > 2"
        }
      }
    ],
    "noDataState": "NoData",
    "execErrState": "Error",
    "annotations": {
      "summary": "Tomcat 应用出现 Java Exception",
      "description": "过去5分钟检测到 {{ $values.A.Value }} 条 Exception/Error 日志，超过阈值 2 条"
    },
    "labels": {
      "severity": "critical",
      "source": "loki-logql"
    }
  }' 2>&1 | head -c 500

echo ""
echo ">>> Step 4: 查询已创建的告警规则..."
curl -s -u ${USER}:${PASS} "${GRAFANA}/api/v1/provisioning/alert-rules" 2>&1 | python3 -c "
import sys,json
rules = json.load(sys.stdin)
for r in rules:
    print(f'  [{r.get(\"uid\",\"?\")[:8]}] {r.get(\"title\",\"?\")}')
print(f'Total rules: {len(rules)}')" 2>&1

echo ""
echo "P1.8 alert rules created."
