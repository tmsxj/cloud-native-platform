# 可观测性总览与运维手册

> 项目沉淀 **两套可观测性方案**，manifest 均保留在仓库，可独立部署 / 对照学习：
> - **方案 A（初版 · 经典三件套）**：Prometheus + Loki + SkyWalking + Elasticsearch
> - **方案 B（演进版 · LGTM + OTel）**：Prometheus + Loki + Grafana + Tempo + OTel Collector + MinIO(S3)
>
> 当前集群实际运行 **方案 B**（方案 A 的 SkyWalking / ES 为省资源已卸载，但 manifest 仍在，可随时切回）。

## 概述

本目录按**可观测性三支柱（Metrics / Logs / Traces）**组织，沉淀了**两套方案**，共享 Metrics 与 NFS 文件存储，差异在 Traces 链路与对象存储后端。两套均以 **Grafana** 为统一可视化入口。

## 两套方案对照

| 支柱 | 方案 A（初版 · 经典三件套） | 方案 B（演进版 · LGTM + OTel，当前运行） |
|------|------|------|
| **M**etrics | Prometheus + AlertManager + Grafana + node-exporter + kube-state-metrics + Pushgateway | 同（不变） |
| **L**ogs | Loki（filesystem 本地 PVC）+ Promtail | Loki（MinIO S3, bucket=`loki`）+ Promtail |
| **T**races | SkyWalking OAP/UI + Java Agent 注入 | OpenTelemetry Collector + Tempo（MinIO S3, bucket=`tempo`） |
| 对象存储 | 无（ES 用 local-path PVC，见 `04-es-storage/`） | MinIO/S3（Tempo 与 Loki 共用，见 `05-otel/`） |
| trace ↔ log 关联 | Grafana `derivedFields → SkyWalking` | Grafana `trace_id` 关联 Tempo + Loki |
| 埋点方式 | SkyWalking Java Agent（`-javaagent`） | OTLP（应用直出 / 边车） |
| 适用场景 | 传统开箱即用的成熟 APM | 云原生标准栈、统一 OTLP、S3 化降本 |

> 💡 两套不是"新旧替代"，而是**同一种可观测性目标下的两种实现路径**：方案 A 让你掌握 SkyWalking/ES 这套成熟 APM；方案 B 让你对齐 CNCF LGTM 标准栈。学习时建议都跑一遍。

**存储双栈**（详见下文「存储架构」）：文件存储走 **NFS**（Grafana/Prometheus 等 PVC），对象存储走 **MinIO/S3**（方案 B 的 Tempo/Loki chunk）。方案 A 的 Elasticsearch 走 local-path PVC，不占 NFS。

**两阶段策略**：监控跑通 → 保存配置 → 删 Pod 腾资源 → 部署 CI/CD + 中间件 → 按需恢复监控。

## 目录结构

```
可观测性/
├── 01-metrics/                         # 📊 指标 — Prometheus + AlertManager + Grafana
│   ├── prometheus-with-alerting.yml    #   Prometheus 主配置（含告警规则引用）
│   ├── prometheus-alerting-rules.yml   #   15 条告警规则（可读版）
│   ├── alertmanager.yml                #   Webhook 路由
│   ├── alertmanager-email.yml          #   邮件通知
│   ├── grafana-dashboard-*.yaml        #   Dashboard Provider / K8s Overview
│   ├── webhook-examples.md             #   飞书/企微 IM 对接模板
│   └── servicemonitor/                 #   Prometheus Operator ServiceMonitor + CR
├── 02-logs/                            # 📜 日志 — Loki(S3/MinIO) + Promtail
│   ├── loki-multitenant/               #   Loki 多租户 (auth_enabled + tenant_id)
│   ├── log-alerting/                   #   日志告警规则
│   ├── loki-pvc.yaml                   #   Loki path_prefix 工作台 PVC
│   └── elasticsearch-pvc.yaml          #   方案 A 的 ES 持久化 PVC（SkyWalking 依赖）
├── 03-traces/                          # 🔍 追踪 — 方案 A 的 SkyWalking 组件（manifest 保留）
│   ├── README.md                       #   方案 A traces 说明（SkyWalking）+ 与方案 B 对照
│   └── agent/                          #   方案 A 的 SkyWalking Java Agent 注入
├── 04-es-storage/                      # ⚠️ 方案 A 的 trace 存储后端（SkyWalking 依赖 ES）
├── 05-otel/                            # 🚀 LGTM 演进 — OTel Collector + Tempo + MinIO
│   ├── minio.yaml                      #   MinIO 对象存储（Tempo 与 Loki 共用 S3 后端）
│   ├── tempo.yaml                      #   Tempo 3.0 单体（后端 MinIO S3）
│   ├── otel-collector.yaml             #   OTel Collector 网关（OTLP 4317/4318）
│   ├── _grafana-datasources.yaml       #   Grafana 数据源（Prometheus/Loki/Tempo）
│   └── README.md                       #   LGTM 完整栈说明（最终版）
├── scripts/                            # 🔧 运维脚本（save/delete/restore）
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
| 数据源 | 3 | Prometheus（默认）+ Loki（logs）+ Tempo（traces，trace_id 关联） |
| Dashboard | 11 | K8s 全套 + Node Exporter + Harbor + 日志-Trace 联动 |

### 部署组件（按三支柱 + 存储分组）

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
| loki | StatefulSet | Loki 2.9.0（`object_store: s3` → MinIO） |
| promtail | DaemonSet ×5 | 日志采集（注入 `tenant_id: demo`） |

#### 🔍 Traces（追踪 · 方案 B，当前运行）
| 组件 | 类型 | 说明 |
|------|------|------|
| otel-collector | Deployment | OpenTelemetry Collector 网关（OTLP 4317/4318） |
| tempo | StatefulSet | Tempo 3.0（后端 MinIO S3） |
| minio | Deployment | MinIO 对象存储（bucket: `tempo` / `loki`） |

#### 🔍 Traces（追踪 · 方案 A，manifest 保留、当前未运行）
| 组件 | 类型 | 说明 |
|------|------|------|
| skywalking-oap | Deployment | SkyWalking OAP Server（接 ES 存储，见 `04-es-storage/`） |
| skywalking-ui | Deployment | SkyWalking UI（端口 8080） |
| elasticsearch | StatefulSet ×3 | SkyWalking trace 存储后端（local-path PVC，已卸载省资源） |
| tomcat-skywalking | Deployment | Tomcat 经 `-javaagent` 注入 SkyWalking Agent（见 `03-traces/agent/`） |

> 📌 方案 A 的 SkyWalking OAP/UI、Elasticsearch 当前**未运行**（为省资源已卸载），manifest 仍保留于 `03-traces/`、`04-es-storage/`，可随时部署切回方案 A。两套 Traces **不可同时跑**（端口/追踪语义不同），切换时按需 scale 对应组件。

### PVC 占用

| PVC | 大小 | 后端 | 用途 |
|-----|------|------|------|
| grafana-nfs | 5Gi | NFS | Grafana 配置 + Dashboard |
| prometheus-nfs | 30Gi | NFS | Prometheus TSDB |
| tomcat-logs-pvc | 5Gi | NFS | Tomcat 应用日志 |
| loki-storage | 5Gi | NFS/local-path | Loki `path_prefix` 本地工作台（compactor 临时目录） |
| storage-alertmanager-0 | 50Mi | NFS | AlertManager 静默规则 |

> MinIO（Tempo/Loki 的真实对象落盘）使用 Pod 本地盘 / emptyDir，**不占 NFS PVC**；对象以 bucket 形式存在 MinIO 中。

---

## 存储架构（NFS 文件存储 + MinIO 对象存储 双栈）

本项目的可观测性数据由**两套互补的存储**承载，二者不是替代关系，而是不同抽象层：

### 1️⃣ NFS — 文件存储（给 Pod 一块共享磁盘）

- **位置**：`存储管理/`（`nfs-provisioner.yaml` + README）
- **实现**：自建 external provisioner，StorageClass `nfs-client`，后端 `h1:/srv/nfs-k8s`（Harbor 物理机）
- **协议**：NFS v4.1，`hard` mount + `timeo=600`（防网络抖动丢 IO）
- **特点**：POSIX 文件系统语义，支持 `ReadWriteMany`（多 Pod 跨节点共享）
- **用途**：Grafana 配置、Prometheus TSDB、Tomcat 日志等**需要文件系统语义**的有状态数据
- **已用 PVC**：`grafana-nfs`(5Gi) / `prometheus-nfs`(30Gi) / `tomcat-logs-pvc`(5Gi) / `loki-storage`(5Gi)

### 2️⃣ MinIO — 对象存储（给应用一个 S3 对象桶）

- **位置**：`05-otel/minio.yaml`（详见 `05-otel/README.md`）
- **实现**：MinIO 单体（兼容 S3 API），运行于 `monitoring` 命名空间
- **访问**：应用通过 HTTP REST（`mc`/`aws cli`/SDK）调用，非 K8s 卷挂载
- **特点**：扁平 key 模型（bucket + key + object），适合一次写多次读、不可变、海量的 chunk/段
- **用途**：Tempo trace 索引/段、Loki chunk —— **Tempo 与 Loki 共用同一 MinIO 实例**
- **bucket**：`tempo`（trace）、`loki`（log chunk）

### 为什么可观测性这么分

Trace/Log chunk 是「一次写、多次读、不可变、海量、按时间分块」的数据，天然适配对象存储的扁平 key 模型（便于生命周期管理、水平扩展、与 S3 生态对齐）；而 Grafana/Prometheus 需要「随机读写、目录层级、原子重命名」的文件系统语义，挂 NFS 盘最省事。**NFS 给"Pod 一块共享磁盘"，MinIO 给"应用一个 S3 对象桶"，在 LGTM 栈里恰好互补。**

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
# ...（同原脚本，导出 configmaps/secrets/deployments/statefulsets/daemonsets/pvc/services）
kubectl get configmap prometheus-server -n $ns -o yaml > "$backup/configmaps/prometheus-server.yaml"
kubectl get configmap alertmanager -n $ns -o yaml > "$backup/configmaps/alertmanager.yaml"
kubectl get configmap grafana -n $ns -o yaml > "$backup/configmaps/grafana.yaml"
kubectl get configmap loki-config -n $ns -o yaml > "$backup/configmaps/loki-config.yaml"
kubectl get configmap promtail-config -n $ns -o yaml > "$backup/configmaps/promtail-config.yaml"
kubectl get configmap otel-collector-config -n $ns -o yaml > "$backup/configmaps/otel-collector-config.yaml"
kubectl get configmap tempo-config -n $ns -o yaml > "$backup/configmaps/tempo-config.yaml"
kubectl get configmap minio-config -n $ns -o yaml > "$backup/configmaps/minio-config.yaml"
Write-Host "✅ 备份完成: $backup"
```

### 第二步：删除 Pod（保留配置）

> 注意：以下为 **方案 B（当前运行）** 的操作命令。切换回 **方案 A** 时，需改 scale `skywalking-oap`/`skywalking-ui`/`elasticsearch` 并注入 Tomcat Agent（见 `03-traces/`、`04-es-storage/`），两套 Traces 不可同时运行。

```powershell
$ns = "monitoring"
# 缩容 Deployment
kubectl scale deployment prometheus-server -n $ns --replicas=0
kubectl scale deployment grafana -n $ns --replicas=0
kubectl scale deployment kube-state-metrics -n $ns --replicas=0
kubectl scale deployment prometheus-prometheus-pushgateway -n $ns --replicas=0
kubectl scale deployment otel-collector -n $ns --replicas=0
# 缩容 StatefulSet
kubectl scale statefulset alertmanager -n $ns --replicas=0
kubectl scale statefulset loki -n $ns --replicas=0
kubectl scale statefulset tempo -n $ns --replicas=0
kubectl scale deployment minio -n $ns --replicas=0
# 删除 DaemonSet
kubectl delete daemonset promtail -n $ns
kubectl delete daemonset node-exporter-prometheus-node-exporter -n $ns
```

### 第三步：恢复监控

```powershell
$ns = "monitoring"
kubectl scale statefulset alertmanager -n $ns --replicas=1
kubectl scale statefulset loki -n $ns --replicas=1
kubectl scale statefulset tempo -n $ns --replicas=1
kubectl scale deployment minio -n $ns --replicas=1
kubectl scale deployment prometheus-server -n $ns --replicas=1
kubectl scale deployment grafana -n $ns --replicas=1
kubectl scale deployment kube-state-metrics -n $ns --replicas=1
kubectl scale deployment prometheus-prometheus-pushgateway -n $ns --replicas=1
kubectl scale deployment otel-collector -n $ns --replicas=1
```

> ⚠️ **执行顺序**：先起 MinIO → Tempo/Loki（依赖 S3）→ OTel Collector → Prometheus/Grafana/Promtail。

---

## 配置修改记录

### 2026-07-09 LGTM 演进（长期17 完成）

1. **Traces 替换**：OpenTelemetry Collector + Tempo（MinIO S3 后端）替换 SkyWalking + Elasticsearch，对齐 LGTM 生产标准
2. **卸载 Elasticsearch**：释放约 6Gi+ worker 内存；SkyWalking OAP/UI 一并卸载
3. **Grafana 数据源**：`derivedFields → SkyWalking` 改为接入 **Tempo**（trace_id 关联 Logs/Traces）
4. **Loki 存储 S3 化**：`common.storage` + `schema_config.object_store` + `compactor.shared_store` 由 `filesystem` → `s3`（MinIO bucket=`loki`），**LGTM 全栈 S3 化**
5. **MinIO 复用**：Tempo 与 Loki 共用同一 MinIO 实例（bucket 隔离），统一对象存储后端
6. 详见 [`05-otel/README.md`](./05-otel/README.md)

### 2026-07-06 Loki 多租户（P2b.13）

- `auth_enabled: true` + Promtail `tenant_id: demo` + Grafana `X-Scope-OrgID: demo`，验证 demo/fake 租户隔离
- 详见 [`02-logs/loki-multitenant/README.md`](./02-logs/loki-multitenant/README.md)

### 2026-07-05 存储管理 + SkyWalking Agent（P2a.14 / P1.6）

- NFS Provisioner 动态供给（StorageClass `nfs-client` → PVC → Bound）
- SkyWalking Java Agent 注入 Tomcat（**方案 A** 的 traces 探针；方案 B 改用 OTLP 埋点，见 `05-otel/`）

### 2026-07-03 资源优化

1. **全组件资源注入** — Grafana、Loki、AlertManager 等加 requests/limits
2. **Prometheus 保留期** — 15d → 7d（`--storage.tsdb.retention.time=7d`）
3. **备份补全 ServiceAccount**
4. **目录重组** — 按三支柱（01-metrics / 02-logs / 03-traces）分组

### 2026-06-23 告警 + 持久化

1. **Prometheus 15 条告警规则** + AlertManager 路由/抑制/webhook
2. **邮件告警** — QQ 邮箱 SMTP（smtp.qq.com:587）
3. **Loki / Elasticsearch 持久化** — 新建 PVC 替换 emptyDir

---

## 待完成

| 项目 | 说明 |
|------|------|
| Grafana Dashboard 导出 | 通过 API 导出 JSON（`scripts/save-monitoring.sh`） |
| 系统日志 journald 补齐 | kubelet/containerd 在 systemd 下走 journald，需 journal stage |
| 更多应用 OTLP 埋点 | ingress-nginx 等服务的 OTel 探针（替代原 SkyWalking 探针） |
| MinIO 生产加固 | 多盘/纠删码、TLS、access key 轮换（当前单副本演示） |
| 告警接收器落地 | webhook-dummy 替换为飞书/企微真实地址（见 `01-metrics/webhook-examples.md`） |

---

## 演示环境 vs 生产环境（差距与标准做法）

> 📌 **定位**：本项目当前是**演示 / 学习级单副本**实现——**架构选型已对齐企业生态**（LGTM + OTel + 对象存储分层），但**工程落地还差一截**（缺 HA、长期存储、真实告警、安全加固、SLO）。本节能讲清「为什么这么选、生产还差什么」，比只说"搭了 LGTM"更有价值。可作为后续演进的基础。

### 差距对照表

| 维度 | 本项目（演示级） | 企业生产标准 |
|------|------|------|
| 高可用 | Prometheus / Grafana / Loki / Tempo / MinIO 全为**单副本** | 核心组件多副本或 HA（Prometheus 配 Sidecar + Thanos；Grafana ≥2 副本） |
| 指标长期存储 | Prometheus 7d 保留、本地 NFS TSDB | 接 Thanos / Mimir / Cortex，长期存储 + 降采样，保留数月~年 |
| 对象存储 | MinIO 单副本、无纠删码 / TLS、access key 明文在 CM | 多盘纠删码或直接使用云厂商 S3（S3/GCS），启用 TLS + key 轮换 |
| 日志生命周期 | MinIO bucket 无过期策略 | 对象存储配 lifecycle 规则（热/冷分层 + 自动过期） |
| 告警落地 | webhook 指向 `webhook-dummy` | 真实接飞书 / 企微 / 电话，配静默、值班路由（on-call） |
| 安全 | Grafana 默认 admin、MinIO key 在 ConfigMap | SSO/LDAP、Secret 管理（Vault / External Secrets）、NetworkPolicy 隔离 |
| SLO / SLI | 仅资源级告警 | 业务 SLO + 错误预算燃烧率告警（Multiwindow Burn-Rate） |
| Trace 采样 | OTel Collector 无显式采样 | tail-based sampling 防 trace 爆炸，关键链路全采、低频链路抽样 |
| 备份 / DR | 仅 `scripts/save` 导出 yaml | PV 快照 + GitOps 配置即代码 + 定期恢复演练 |
| 端点暴露 | 可观测性端点未走 Ingress/TLS | Grafana / 端点经 Ingress + TLS，最小化对外暴露 |

### 生产环境下标准做法（按组件）

- **Metrics**：Prometheus Operator 托管；Thanos Sidecar + 对象存储做全局视图与长期保留；Recording Rule 预聚合降负载；多副本 AlertManager。
- **Logs**：Loki 生产直接用云 S3（或 MinIO 纠删码集群）；`compactor` 与 `index` 分离；按 namespace/租户设 retention；日志告警接 AlertManager。
- **Traces**：Tempo 后端接云 S3；OTel Collector 部署为 **Gateway + Agent 两层**，Gateway 做 tail-based sampling 与批处理；高吞吐时 Collector 水平扩容。
- **可视化**：Grafana 多副本 + 数据库外置（PostgreSQL）；接入 SSO；DataSource/ Dashboard 用 Terraform 或 GitOps 管理。
- **告警**：AlertManager 接真实 IM（飞书/企微）与 on-call（如 PagerDuty）；基于 SLO 的燃烧率告警；重要告警电话兜底。
- **安全**：所有 Secret 走 External Secrets Operator 从 Vault/云密钥管理同步；Grafana/MinIO 启用 TLS；NetworkPolicy 限制组件间访问。
- **可靠性**：核心组件配 PDB（PodDisruptionBudget）+ 反亲和；PV 用快照备份；用 ArgoCD 做 GitOps 持续同步。

### 演进路线（优先级建议）

1. **告警真实落地**（飞书/企微）—— 投入小、感知强，先把 `webhook-dummy` 换掉
2. **对象存储加固** —— MinIO 纠删码 / 换云 S3 + 日志 lifecycle 过期，消除单点丢数据风险
3. **指标长期存储** —— Prometheus 接 Thanos/Mimir，解决 7d 保留太短
4. **关键组件 HA** —— Grafana / AlertManager / Collector 多副本 + PDB
5. **安全加固** —— Grafana SSO + Secret 管理 + NetworkPolicy
6. **SLO 体系** —— 从资源告警升级到业务 SLO 燃烧率告警

> 以上为**演进 checklist**，可按实际资源逐步补齐；本项目作为基础架构已具备正确的选型与清晰的扩展路径。

---

## 文件清单

### 📊 01-metrics（指标）
| 文件 | 用途 |
|------|------|
| `01-metrics/prometheus-with-alerting.yml` | Prometheus 主配置（含告警规则引用） |
| `01-metrics/prometheus-alerting-rules.yml` | Prometheus 告警规则（15 条，可读版本） |
| `01-metrics/alertmanager.yml` | AlertManager 配置（Webhook 路由） |
| `01-metrics/alertmanager-email.yml` | AlertManager 邮件通知配置 |
| `01-metrics/grafana-dashboard-*.yaml` | Dashboard Provider / K8s Overview |
| `01-metrics/webhook-examples.md` | 飞书+企业微信 webhook 配置案例 |
| `01-metrics/servicemonitor/` | Prometheus Operator ServiceMonitor + CR |

### 📜 02-logs（日志）
| 文件 | 用途 |
|------|------|
| `02-logs/loki-multitenant/README.md` | Loki 多租户（auth_enabled + tenant_id） |
| `02-logs/log-alerting/` | 日志告警规则 |
| `02-logs/loki-pvc.yaml` | Loki `path_prefix` 工作台 PVC |
| `02-logs/elasticsearch-pvc.yaml` | 方案 A 的 ES 持久化 PVC（SkyWalking 依赖；当前未用） |

### 🔍 03-traces（方案 A 的 SkyWalking 组件 · manifest 保留）
| 文件 | 用途 |
|------|------|
| `03-traces/README.md` | 方案 A traces 说明（SkyWalking）+ 与方案 B 对照 |
| `03-traces/agent/README.md` | 方案 A 的 SkyWalking Java Agent 注入（Tomcat `-javaagent`） |
| `03-traces/agent/tomcat-skywalking-deploy.yaml` | SkyWalking Agent 注入后的 Tomcat 部署清单 |

### 🗄️ 04-es-storage（方案 A 的 trace 存储后端）
| 文件 | 用途 |
|------|------|
| `04-es-storage/es-cluster.yaml` | ES 3 节点集群（SkyWalking trace 存储） |
| `04-es-storage/README.md` | ES 集群部署 / 踩坑 / 面试要点 |

### 🚀 05-otel（LGTM 演进 · 当前形态）
| 文件 | 用途 |
|------|------|
| `05-otel/minio.yaml` | MinIO 对象存储（Tempo 与 Loki 共用 S3 后端） |
| `05-otel/tempo.yaml` | Tempo 3.0 单体（后端 MinIO S3） |
| `05-otel/otel-collector.yaml` | OTel Collector 网关（OTLP 4317/4318） |
| `05-otel/_grafana-datasources.yaml` | Grafana 数据源（Prometheus/Loki/Tempo） |
| `05-otel/README.md` | LGTM 完整栈说明（最终版） |

### 🔧 scripts / 其他
| 文件/目录 | 用途 |
|------|------|
| `scripts/save-monitoring.sh` | 一键保存脚本 |
| `scripts/delete-monitoring.sh` | 一键删除 Pod 脚本 |
| `scripts/restore-monitoring.sh` | 一键恢复脚本 |
| `argocd/application.yaml` | ArgoCD 应用定义 |
| `backup-*/` | 备份输出目录 |
