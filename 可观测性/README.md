# 监控配置管理 — 保存/删除/恢复手册

## 概述

本目录包含 monitoring 命名空间所有组件的配置管理和操作脚本，按**可观测性三支柱**组织。

**两阶段策略**：监控跑通 → 保存配置 → 删 Pod 腾资源 → 部署 CI/CD + 中间件 → 按需恢复监控。

## 目录结构

```
可观测性/
├── 01-metrics/                         # 📊 指标 — Prometheus + AlertManager + Grafana
│   ├── prometheus-with-alerting.yml    #   Prometheus 采集配置
│   ├── prometheus-alerting-rules.yml   #   15条告警规则
│   ├── alertmanager.yml                #   Webhook 告警路由
│   ├── alertmanager-email.yml          #   邮件告警通知
│   └── webhook-examples.md             #   飞书/企微 IM 对接模板
├── 02-logs/                            # 📜 日志 — Loki + Elasticsearch
│   ├── elasticsearch-pvc.yaml          #   ES PVC 修复
│   └── loki-pvc.yaml                   #   Loki PVC 修复
├── 03-traces/                          # 🔍 追踪 — SkyWalking OAP + UI
│   └── README.md                       #   预留，SkyWalking 配置后续补充
├── scripts/                            # 🔧 运维脚本
│   ├── save-monitoring.sh              #   一键保存
│   ├── restore-monitoring.sh           #   一键恢复
│   └── delete-monitoring.sh            #   一键删除 Pod
├── argocd/                             # ArgoCD 应用定义
├── backup-*/                           # 历史备份
└── README.md                           # 本文件
```

---

## 当前集群监控清单

### Prometheus 采集目标（11 个 job）

| Job | 目标 |
|-----|------|
| kubernetes-api-servers | K8s API Server |
| kubernetes-nodes | 节点指标 |
| kubernetes-nodes-cadvisor | 容器指标 (cAdvisor) |
| kubernetes-pods | 带 `prometheus.io/scrape` 注解的 Pod |
| kubernetes-pods-slow | 低频抓取 |
| kubernetes-service-endpoints | Service 端点 |
| kubernetes-service-endpoints-slow | 低频抓取 |
| kubernetes-services | Blackbox 探测 |
| prometheus | Prometheus 自身 |
| prometheus-pushgateway | Pushgateway |
| harbor | Harbor 节点 (192.168.1.61:9090) |

### 告警规则（15 条，8 组）

| 分组 | 规则 | 严重级别 |
|------|------|---------|
| node-alerts | CPU > 80%/95%、内存 > 85%/95%、磁盘耗尽、磁盘 > 85%、文件系统只读 | warning/critical |
| pod-alerts | CrashLooping、NotReady、长时间 Pending | warning |
| deployment-alerts | 副本数不匹配 | warning |
| statefulset-alerts | 副本异常 | warning |
| pvc-alerts | 空间 < 15% | warning |
| prometheus-alerts | 目标下线、停止采集样本 | critical |
| watchdog | 心跳检测（始终触发） | none |

### AlertManager 配置

- **分组**: 按 `alertname` + `namespace` 合并
- **路由**: `critical` → webhook-critical, `warning` → webhook-warning
- **抑制**: 节点宕机 → 抑制 Pod 级别告警
- **Receiver**: 三个 webhook（当前指向 `webhook-dummy:8080`，待替换为实际通知地址）

### Grafana 状态

| 类型 | 数量 | 说明 |
|------|------|------|
| 数据源 | 2 | Prometheus (默认) + Loki (with derivedFields → SkyWalking) |
| Dashboard | 11 | K8s 全套 + Node Exporter + Harbor + 日志-Trace 联动 |

### 部署组件（19 个 Pod，按三支柱分组）

#### 📊 Metrics（指标）
| 组件 | 类型 | 说明 |
|------|------|------|
| prometheus-server | Deployment | Prometheus v3.11.3 |
| alertmanager | StatefulSet | AlertManager v0.25.0 |
| grafana | Deployment | Grafana 12.3.1 |
| node-exporter | DaemonSet ×5 | 主机指标 |
| kube-state-metrics | Deployment | K8s 对象指标 |
| prometheus-pushgateway | Deployment | 短任务指标 |

#### 📜 Logs（日志）
| 组件 | 类型 | 说明 |
|------|------|------|
| loki | StatefulSet | Loki 2.9.0 |
| promtail | DaemonSet ×5 | 日志采集 |
| elasticsearch | StatefulSet | SkyWalking trace 存储 |

#### 🔍 Traces（追踪）
| 组件 | 类型 | 说明 |
|------|------|------|
| skywalking-oap | Deployment | SkyWalking OAP 9.7.0 |
| skywalking-ui | Deployment | SkyWalking UI |

### PVC 占用

| PVC | 大小 | 用途 |
|-----|------|------|
| prometheus-server | 50Gi | Prometheus TSDB |
| grafana | 10Gi | Grafana 配置 + Dashboard |
| loki-storage | 5Gi | Loki 日志存储 |
| elasticsearch-data | 10Gi | Elasticsearch trace 数据 |
| storage-alertmanager-0 | 50Mi | AlertManager 静默规则 |

---

## 操作流程

### 第一步：保存配置

```bash
# Linux/Mac/Git Bash
cd "f:/项目管理2026/项目实战/可观测性"
bash scripts/save-monitoring.sh
```

**Windows PowerShell（逐条执行）**:

```powershell
$ns = "monitoring"
$backup = "f:/项目管理2026/项目实战/可观测性/backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
New-Item -ItemType Directory -Path "$backup/configmaps" -Force | Out-Null
New-Item -ItemType Directory -Path "$backup/secrets" -Force | Out-Null
New-Item -ItemType Directory -Path "$backup/services" -Force | Out-Null
New-Item -ItemType Directory -Path "$backup/deployments" -Force | Out-Null
New-Item -ItemType Directory -Path "$backup/statefulsets" -Force | Out-Null
New-Item -ItemType Directory -Path "$backup/daemonsets" -Force | Out-Null
New-Item -ItemType Directory -Path "$backup/pvc" -Force | Out-Null

# 导出 ConfigMap
kubectl get configmap prometheus-server -n $ns -o yaml > "$backup/configmaps/prometheus-server.yaml"
kubectl get configmap alertmanager -n $ns -o yaml > "$backup/configmaps/alertmanager.yaml"
kubectl get configmap grafana -n $ns -o yaml > "$backup/configmaps/grafana.yaml"
kubectl get configmap loki-config -n $ns -o yaml > "$backup/configmaps/loki-config.yaml"
kubectl get configmap promtail-config -n $ns -o yaml > "$backup/configmaps/promtail-config.yaml"

# 导出 Secret
kubectl get secret grafana -n $ns -o yaml > "$backup/secrets/grafana.yaml"

# 导出所有 Deployment/StatefulSet/DaemonSet/Service/PVC/Ingress
kubectl get deployment -n $ns -o yaml > "$backup/deployments/all.yaml"
kubectl get statefulset -n $ns -o yaml > "$backup/statefulsets/all.yaml"
kubectl get daemonset -n $ns -o yaml > "$backup/daemonsets/all.yaml"
kubectl get service -n $ns -o yaml > "$backup/services/all.yaml"
kubectl get pvc -n $ns -o yaml > "$backup/pvc/all.yaml"
kubectl get ingress -n $ns -o yaml > "$backup/ingress.yaml"

Write-Host "✅ 备份完成: $backup"
```

### 第二步：删除 Pod（保留配置）

```bash
# Linux/Mac/Git Bash
bash scripts/delete-monitoring.sh
```

**Windows PowerShell（逐条执行）**:

```powershell
$ns = "monitoring"

# 缩容 Deployment
kubectl scale deployment prometheus-server -n $ns --replicas=0
kubectl scale deployment grafana -n $ns --replicas=0
kubectl scale deployment kube-state-metrics -n $ns --replicas=0
kubectl scale deployment prometheus-prometheus-pushgateway -n $ns --replicas=0
kubectl scale deployment skywalking-oap -n $ns --replicas=0
kubectl scale deployment skywalking-ui -n $ns --replicas=0

# 缩容 StatefulSet
kubectl scale statefulset alertmanager -n $ns --replicas=0
kubectl scale statefulset elasticsearch -n $ns --replicas=0
kubectl scale statefulset loki -n $ns --replicas=0

# 删除 DaemonSet
kubectl delete daemonset promtail -n $ns
kubectl delete daemonset node-exporter-prometheus-node-exporter -n $ns
```

### 第三步：恢复监控

```bash
# Linux/Mac/Git Bash
bash scripts/restore-monitoring.sh
```

**Windows PowerShell（逐条执行）**:

```powershell
$ns = "monitoring"

# 恢复 DaemonSet（先启动采集器）
kubectl apply -f "f:/项目管理2026/项目实战/可观测性/backup-*/daemonsets/all.yaml"

# 恢复 StatefulSet
kubectl scale statefulset alertmanager -n $ns --replicas=1
kubectl scale statefulset elasticsearch -n $ns --replicas=1
kubectl scale statefulset loki -n $ns --replicas=1

# 恢复 Deployment
kubectl scale deployment prometheus-server -n $ns --replicas=1
kubectl scale deployment grafana -n $ns --replicas=1
kubectl scale deployment kube-state-metrics -n $ns --replicas=1
kubectl scale deployment prometheus-prometheus-pushgateway -n $ns --replicas=1
kubectl scale deployment skywalking-oap -n $ns --replicas=1
kubectl scale deployment skywalking-ui -n $ns --replicas=1
```

---

## 配置修改记录

### 2026-07-03 资源优化

1. **SkyWalking OAP 内存控制** — `JAVA_OPTS=-Xms512m -Xmx1024m`，资源 requests: 500m CPU/1Gi，limits: 1.5 CPU/1.5Gi
2. **全组件资源注入** — Grafana、SkyWalking UI、Loki、AlertManager、kube-state-metrics、Pushgateway 全部加上 requests/limits
3. **Prometheus 保留期** — 15d → 7d（`--storage.tsdb.retention.time=7d`）
4. **备份补全 ServiceAccount** — 新备份 `backup-20260703-optimized` 含 SA
5. **清理 snownlp 残留** — 旧备份中 loadgen-script、snownlp-demo-app 已删除
6. **目录重组** — 按三支柱（01-metrics / 02-logs / 03-traces）分组

### 2026-06-23 新增

1. **Prometheus 告警规则** (`prometheus-server` ConfigMap → `alerting_rules.yml`)
   - 15 条规则覆盖节点/Pod/Deployment/StatefulSet/PVC/Prometheus 自身

2. **AlertManager 路由配置** (`alertmanager` ConfigMap → `alertmanager.yml`)
   - 按 severity 分组路由，抑制规则，webhook receiver

3. **Prometheus alerting 地址** — 补上遗漏的 `alertmanagers → alertmanager.monitoring:9093`

4. **邮件告警** — QQ 邮箱 SMTP（smtp.qq.com:587），三级路由全部验证通过

### 2026-06-23 修复（三支柱补齐）

1. **Loki 持久化存储** — 新建 PVC `loki-storage` (5Gi)，替换 emptyDir
2. **Elasticsearch 持久化存储** — 新建 PVC `elasticsearch-data` (10Gi)，替换 emptyDir
3. **Loki 日志告警** — `ruler.alertmanager_url: http://alertmanager.monitoring:9093`

### 待完成

| 项目 | 说明 |
|------|------|
| ~~飞书/企微集成~~ | ~~部署 prometheus-webhook-dingtalk~~ → [配置案例文档](01-metrics/webhook-examples.md) 已完成 |
| Grafana Dashboard 导出 | 通过 API 导出 JSON（`scripts/save-monitoring.sh` 第8步） |
| ~~系统日志采集~~ | ~~Promtail 采集 kubelet/containerd 日志~~ → 已完成（host-logs / kubelet-logs / docker-daemon-logs） |
| 系统日志 journald 补齐 | kubelet/containerd 在 systemd 下走 journald，需 journal stage |
| 更多应用 trace 埋点 | ingress-nginx 等服务的 SkyWalking 探针 |

---

## 文件清单

### 📊 01-metrics（指标）
| 文件 | 用途 |
|------|------|
| `01-metrics/prometheus-with-alerting.yml` | Prometheus 主配置（含告警规则引用） |
| `01-metrics/prometheus-alerting-rules.yml` | Prometheus 告警规则（15条，可读版本） |
| `01-metrics/alertmanager.yml` | AlertManager 配置（Webhook 路由） |
| `01-metrics/alertmanager-email.yml` | AlertManager 邮件通知配置 |
| `01-metrics/webhook-examples.md` | 飞书+企业微信 webhook 配置案例 |

### 📜 02-logs（日志）
| 文件 | 用途 |
|------|------|
| `02-logs/elasticsearch-pvc.yaml` | Elasticsearch PVC 修复 |
| `02-logs/loki-pvc.yaml` | Loki PVC 修复 |

### 🔍 03-traces（追踪）
| 文件 | 用途 |
|------|------|
| `03-traces/README.md` | 预留，SkyWalking 配置后续补充 |

### 🔧 scripts（运维脚本）
| 文件 | 用途 |
|------|------|
| `scripts/save-monitoring.sh` | 一键保存脚本 |
| `scripts/delete-monitoring.sh` | 一键删除 Pod 脚本 |
| `scripts/restore-monitoring.sh` | 一键恢复脚本 |

### 其他
| 文件/目录 | 用途 |
|------|------|
| `argocd/application.yaml` | ArgoCD 应用定义 |
| `backup-*/` | 备份输出目录 |
