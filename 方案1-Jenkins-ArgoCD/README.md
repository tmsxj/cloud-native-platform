# Jenkins（CI 持续集成工具） + ArgoCD GitOps CI/CD 总结

> 基于自建 K8s 集群（Harbor + ArgoCD（GitOps 持续交付工具） + Jenkins + Git Server）的真实环境验证
> 验证项目：`snownlp-observability-demo`（SnowNLP 情感分析 + 可观测性三支柱）
> 基础设施：`可观测性`（Prometheus/Grafana/Loki/SkyWalking（APM 调用链追踪） 监控体系）

---

## 一、架构总览

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        GitOps CI/CD 全链路                                 │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌──────────┐    git push     ┌──────────────┐                           │
│  │ 开发者     │──────────────▶ │  Git Server   │                           │
│  │ 修改代码   │                │  (git-daemon) │                           │
│  └──────────┘                └──────┬───────┘                           │
│                                     │                                     │
│                                     ▼ (git clone)                         │
│  ┌──────────────────────────────────────────────────────────────────┐    │
│  │                    Jenkins CI Pipeline (7 Stage)                   │    │
│  │                                                                    │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐          │    │
│  │  │ Stage 1  │  │ Stage 2  │  │ Stage 3  │  │ Stage 4  │          │    │
│  │  │ Checkout │─▶│ Unit     │─▶│ Build    │─▶│ Push     │          │    │
│  │  │ 拉取代码  │  │ Test     │  │ Image    │  │ Image    │          │    │
│  │  │          │  │ Pytest   │  │ 构建镜像  │  │ 推送镜像  │          │    │
│  │  └──────────┘  └──────────┘  └──────────┘  └────┬─────┘          │    │
│  │                                                  │                 │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐       │                 │    │
│  │  │ Stage 7  │◀─│ Stage 6  │◀─│ Stage 5  │◀──────┘                 │    │
│  │  │ Wait     │  │ Git Push │  │ Update   │  sed 替换                │    │
│  │  │ Sync     │  │ 提交推送  │  │ GitOps   │  deployment.yaml        │    │
│  │  └──────────┘  └──────────┘  └──────────┘                         │    │
│  └───────────────────────┬────────────────────────────────────────────┘    │
│                          │ git push (更新了 deployment.yaml)               │
│                          ▼                                                  │
│  ┌──────────────────────────────────────────────────────────────────┐    │
│  │                      ArgoCD GitOps Engine                          │    │
│  │                                                                    │    │
│  │  ┌────────────────────────────────────────────────────────────┐  │    │
│  │  │  Application: snownlp-demo                                  │  │    │
│  │  │  Repo: git://git-server.git.svc/snownlp-observability-demo  │  │    │
│  │  │  Path: 01-app/                                              │  │    │
│  │  │  Target: monitoring namespace                               │  │    │
│  │  │  Sync: automated (selfHeal + prune)                         │  │    │
│  │  └────────────────────────────────────────────────────────────┘  │    │
│  │                          │                                        │    │
│  │   每 3min 检测 Git 变化  │  检测到 deployment.yaml 变更            │    │
│  │                          ▼                                        │    │
│  │  ┌────────────────────────────────────────────────────────────┐  │    │
│  │  │  kubectl apply -f 01-app/deployment.yaml                    │  │    │
│  │  │  kubectl apply -f 01-app/service.yaml                       │  │    │
│  │  └────────────────────────────────────────────────────────────┘  │    │
│  └───────────────────────┬──────────────────────────────────────────┘    │
│                          │                                                  │
│                          ▼                                                  │
│  ┌──────────────────────────────────────────────────────────────────┐    │
│  │      Kubernetes Cluster (monitoring namespace)                     │    │
│  │                                                                   │    │
│  │  ┌─────────────────────┐  ┌─────────────────┐                    │    │
│  │  │ snownlp-demo        │  │ snownlp-demo    │                    │    │
│  │  │ Deployment          │  │ Service         │                    │    │
│  │  │ image: ...:build-N  │  │ port: 8000      │                    │    │
│  │  └─────────┬───────────┘  └────────┬────────┘                    │    │
│  │            │                       │                              │    │
│  │            ▼                       ▼                              │    │
│  │  ┌─────────────────────────────────────────────────────────┐    │    │
│  │  │  可观测性三支柱                                             │    │    │
│  │  │  Metrics → Prometheus (scrape /metrics)                  │    │    │
│  │  │  Logs    → Promtail → Loki (trace_id 关联)               │    │    │
│  │  │  Traces  → SkyWalking Agent → OAP → Elasticsearch       │    │    │
│  │  │  Panels  → Grafana (Loki derivedFields → SkyWalking)     │    │    │
│  │  └─────────────────────────────────────────────────────────┘    │    │
│  └──────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 二、两个项目体系

本方案由两个 GitOps（以 Git 为唯一真相源的运维模式） 项目组成，通过 **monitoring 命名空间** 关联：

### 2.1 snownlp-observability-demo（业务应用 + CI/CD（持续集成/持续交付））

```
snownlp-observability-demo/
├── Jenkinsfile                    ← CI 流水线定义（7 Stage）
├── 01-app/                        ← 被 ArgoCD 监听的业务目录
│   ├── app.py                     ← FastAPI + SnowNLP 情感分析
│   ├── Dockerfile                 ← 镜像构建（sw-python agent）
│   ├── deployment.yaml            ← ⚡ GitOps 核心文件：由 Jenkins 自动更新
│   ├── service.yaml               ← K8s Service（静态不变）
│   ├── requirements.txt           ← Python 依赖
│   ├── loadgen.py                 ← 持续压测脚本
│   └── loadgen-deployment.yaml    ← 压测器 Deployment
├── 02-promtail/                   ← 日志采集（可观测性支柱）
├── 03-loki/                       ← 日志存储
├── 04-grafana/                    ← 数据源配置 + 关联跳转
├── 05-ingress/                    ← 外部访问入口
└── argocd/
    └── snownlp-demo-app.yaml      ← ArgoCD Application 定义
```

### 2.2 可观测性（监控基础设施）

```
可观测性/
├── prometheus-with-alerting.yml   ← Prometheus 主配置（11 个 scrape job）
├── prometheus-alerting-rules.yml  ← 15 条告警规则（8 组）
├── alertmanager.yml               ← Webhook 告警路由
├── alertmanager-email.yml         ← QQ 邮箱通知
├── webhook-examples.md            ← 飞书/企微 Webhook 集成
├── save-monitoring.sh             ← 一键保存监控栈
├── delete-monitoring.sh           ← 一键缩容释放资源
├── restore-monitoring.sh          ← 一键恢复监控栈
├── argocd/
│   └── application.yaml           ← ArgoCD Application (monitoring-stack)
├── fixes/
│   ├── elasticsearch-pvc.yaml     ← ES 持久化存储修复
│   └── loki-pvc.yaml              ← Loki 持久化存储修复
└── backup-20260624-012453/        ← 集群快照备份
```

---

## 三、GitOps 核心工作原理

### 核心思想

> CI 不直接操作 K8s（不用 `kubectl apply`），而是 **修改 Git 中的清单文件**，让 ArgoCD 自动检测并同步。
> **Git = 唯一真相源（Single Source of Truth）**

### 完整数据流

```
Step 1: 开发者 git push 代码到 main 分支
    ↓
Step 2: Jenkins 触发 Pipeline（Webhook 或 手动触发）
    ↓
Step 3: Jenkins Stage 1 → git clone 拉取代码
    ↓
Step 4: Jenkins Stage 2 → docker build 构建镜像
        镜像标签格式: yyyyMMdd-HHmmss-{BUILD_NUMBER}
    ↓
Step 5: Jenkins Stage 3 → docker push 推送至 Harbor (192.168.1.61)
    ↓
Step 6: Jenkins Stage 4 → sed 替换 01-app/deployment.yaml 中的 image: 行
        将 image: ...:旧tag → image: ...:新tag
    ↓
Step 7: Jenkins Stage 5 → git commit + git push 提交变更
    ↓
Step 8: ArgoCD 检测到 Git 仓库中 01-app/ 目录变化（默认 3min 轮询）
    ↓
Step 9: ArgoCD 自动执行 kubectl apply，将新镜像部署到 K8s
    ↓
Step 10: K8s 滚动更新 Deployment，新 Pod 启动并注册到 SkyWalking
```

### 为什么用 sed 而不是 Kubectl？

| 方式 | 操作 | 问题 |
|------|------|------|
| ❌ `kubectl set image` | CI 直接操作 K8s（Kubernetes，容器编排引擎） | ArgoCD 不知道变更，下次 sync 会回滚 |
| ❌ `kubectl apply -f` | CI 直接 apply 新 YAML | 绕过了 GitOps，违反唯一真相源原则 |
| ✅ `sed → git commit → git push` | 修改 Git 清单 | ArgoCD 自动检测、自动同步、可审计、可回滚 |

---

## 四、环境信息

| 组件 | 地址 | 凭证 | 用途 |
|------|------|------|------|
| **Jenkins** | `http://jenkins.test:31716` | 无需登录 (Unsecured) | CI 流水线 |
| **ArgoCD** | `http://argocd.test:31716` | `admin` / `wRRzfFrgasxcpwwq` | GitOps CD |
| **Harbor（私有镜像仓库）** | `192.168.1.61` | admin / Harbor12345 | 镜像仓库 |
| **Git Server** | `git://git-server.git.svc.cluster.local` | 无需认证 | 源代码管理 |
| **K8s 集群** | `https://kubernetes.default.svc` | ServiceAccount | 部署目标 |

### 监控组件（monitoring 命名空间）

| 组件 | 地址 | 说明 |
|------|------|------|
| **Grafana（可视化面板）** | `http://grafana.lab.local:31716` | admin / admin |
| **Prometheus（指标监控系统）** | `http://prometheus.lab.local:31716` | 指标查询 |
| **SkyWalking UI** | `http://skywalking.lab.local:31716` | 调用链追踪 |
| **SnowNLP Demo** | `http://snownlp.lab.local:31716` | 情感分析 Demo |

---

## 五、两个 ArgoCD Application

| 属性 | snownlp-demo | monitoring-stack |
|------|-------------|------------------|
| **Git 仓库** | snownlp-observability-demo | 可观测性 |
| **监听路径** | `01-app/` | `.`（根目录，递归） |
| **目标命名空间** | `monitoring` | `monitoring` |
| **自动同步** | ✅ prune=true, selfHeal=true | ✅ prune=false(安全), selfHeal=true |
| **重试** | 5 次，指数退避，最多 3min | 3 次，指数退避，最多 3min |
| **触发方式** | Jenkins 更新 deployment.yaml | 手动更新配置 YAML |
| **排除** | 无 | backup-*, fixes, *.sh, *.md |

---

## 六、项目关联关系

```
monitoring 命名空间（统一的可观测性环境）
│
├── [监控基础设施] ← 可观测性 项目管理
│   ├── Prometheus (采集 + 告警)
│   ├── AlertManager (告警通知)
│   ├── Grafana (可视化)
│   ├── Loki + Promtail (日志)
│   ├── SkyWalking OAP + UI (追踪)
│   ├── node-exporter (节点指标)
│   └── kube-state-metrics (K8s 指标)
│
└── [业务应用] ← snownlp-observability-demo 项目管理
    ├── snownlp-demo Deployment (情感分析 API)
    ├── snownlp-demo Service (ClusterIP:8000)
    ├── snownlp-loadgen Deployment (持续压测)
    └── Ingress (统一外部入口)
```

**关联点**：
- 业务应用的 Prometheus 注解 → `scrape by Prometheus`
- 业务应用的 SkyWalking env → `report to skywalking-oap.monitoring:11800`
- 业务日志的 trace_id → `Promtail extract → Loki（日志系统） → Grafana derivedFields → SkyWalking URL`
- Ingress（入口规则） 统一路由 → `snownlp.lab.local → snownlp-demo:8000`

---

## 七、Jenkins Pipeline（流水线） 7 Stage 详解

### Stage 1: Checkout
- 从 Git Server 拉取 `main` 分支代码
- 内网环境使用 `git://` 协议（Git Daemon 9418 端口）
- 获取 `GIT_COMMIT`、`BRANCH_NAME` 等环境变量

### Stage 2: Unit Test (Pytest) 【P0 新增】
- 在 `01-app/` 目录下运行 Pytest
- 安装依赖后执行 pytest --tb=short --maxfail=5
- 演示环境放宽策略：测试失败不阻塞构建
- 面试亮点："CI Pipeline 包含质量门禁，先测试再构建"

### Stage 3: Build Image
- 在 `01-app/` 目录下执行 `docker build`
- 同时打上 `BUILD_TIMESTAMP-BUILD_NUMBER` 和 `latest` 两个标签
- 添加 OCI 标签：`git.commit`、`build.number`、`build.time`
- 内网环境使用本地 Harbor 基础镜像 `192.168.1.61/library/python:3.11-slim`

### Stage 4: Push Image
- 推送带时间戳的版本标签和 latest 标签到 Harbor
- Harbor 项目：`monitoring/snownlp-demo`

### Stage 5: Update GitOps Manifests 【核心步骤】
- 用 sed 替换 `01-app/deployment.yaml` 中的 `image:` 行
- 匹配模式：`image: 192.168.1.61/monitoring/snownlp-demo:任意tag`
- 替换为：`image: 192.168.1.61/monitoring/snownlp-demo:新构建号`
- 验证替换结果：`grep 'image:' deployment.yaml`

### Stage 6: Git Commit & Push
- 配置 Git 用户：`jenkins@cicd.local` / `Jenkins CI`
- 提交变更信息包含：构建号、镜像标签、Git commit SHA
- 推送到 main 分支（容错处理：离线环境跳过 push）

### Stage 7: Wait ArgoCD Sync
- 等待 ArgoCD 自动检测 Git 变化并同步
- 可选：主动调用 ArgoCD API 触发即时同步

---

## 八、目录结构

```
方案1-Jenkins-ArgoCD/
├── README.md                 ← 架构总览、GitOps 流程图、环境信息
├── 关键配置详解.md            ← 每份配置的设计意图、变量含义、关键决策
├── 故障排查手册.md            ← 11 个实战踩坑场景 + 快速诊断命令
├── 项目结构对照.md            ← 双项目架构关系、文件对照、资源部署清单
├── 端到端操作实录.md          ★ 从零搭建全过程的命令实录
└── 配置文件/                  ★ 所有 YAML/XML/Shell 独立文件（带中文注释）
    ├── git-server/            ← Git Server 部署配置
    ├── jenkins/               ← Jenkins 部署 + Pipeline Job XML
    ├── argocd/                ← ArgoCD 仓库注册 Secret
    ├── scripts/               ← 一键初始化脚本
    └── README.md              ← 配置目录使用指南 + 变量替换说明
```

---

## 九、文档关系说明

| 文档 | 适合场景 |
|------|---------|
| **端到端操作实录** | 新人上手、环境重建、理解"到底敲了什么命令" |
| **配置文件/** | 直接复制 YAML/XML/Shell，避免文档格式混乱 |
| **关键配置详解** | 理解每份 YAML/Groovy 为什么这样写 |
| **故障排查手册** | 出问题时快速定位和修复 |
| **项目结构对照** | 理解两个项目之间的关联关系 |
| **README（本文）** | 快速了解整体架构和核心原理 |
