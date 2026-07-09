# 项目实战：K8s 全链路 CI/CD + 可观测性 + 灰度发布

> 基于自建 5 节点 K8s 集群的 DevOps 实战项目，覆盖 **CI/CD 三方案 → 可观测性三大支柱 → 灰度发布 → K8s 三基石** 全链路。
>
> 📅 最近更新: 2026-07-09 | 状态: P0~P2b + 长期16 eBPF 全部完成 ✅ | 集群已开机，Cilium/Hubble(eBPF) 栈健康

---

## 这是什么？

一套完整的 K8s DevOps 落地工程，从零搭建了 **Harbor(镜像仓库) + Jenkins/GitLab CI(持续集成) + ArgoCD(GitOps 持续部署) + Prometheus/Grafana/Loki/SkyWalking(可观测性) + Argo Rollouts(灰度发布)**。

可以作为 DevOps/SRE 岗位的 **面试作品** 或 **企业内部 DevOps 平台参考模板**。

---

## 我是谁？该从哪里开始？

| 你的角色 | 推荐路径 | 耗时 |
|---------|---------|:--:|
| 🆕 **新人/面试官**，想快速了解项目 | 1. 看本文档 ↓ → 2. [全局部署指南](./全局参考/全局部署指南.md) | 10 min |
| 🔧 **运维**，想在新集群上部署 | 1. [全局部署指南](./全局参考/全局部署指南.md) → 2. 修改 `部署工具/env.sh` → 3. 选一个方案执行 | 30 min |
| 💻 **开发**，想知道 CI/CD 怎么串的 | [方案1 README](./方案1-Jenkins-ArgoCD/README.md)（Jenkins）或 [方案2 README](./方案2-GitLab-ArgoCD/README.md)（GitLab） | 15 min |
| 📊 **SRE**，关注监控和告警 | [可观测性/](./可观测性/) 下的 prometheus 配置 + 告警规则 | 20 min |
| 🎯 **面试准备**，需要讲清楚全链路 | [三套方案对比](./CI-CD总览/CI-CD-GitOps-三套方案对比.md) + [CICD 生态工具速览](./CI-CD总览/CICD生态工具速览-理论补充.md) + [K8s 三基石](./K8s基础/K8s-三基石-HPA-存储-Ingress.md) | 60 min |

---

## 项目全景

```
                                ┌──────────────────────┐
                                │    Harbor 镜像仓库    │
                                │    192.168.1.61       │
                                └──────────┬───────────┘
                                           │ push/pull 镜像
        ┌──────────────────────────────────┼──────────────────────────────────┐
        │                                  │                                  │
        ▼                                  ▼                                  ▼
┌───────────────┐                ┌───────────────┐                ┌───────────────┐
│   方案1        │                │   方案2        │                │   方案3        │
│ Jenkins CI    │                │ GitLab CI     │                │ Argo Rollouts │
│ + ArgoCD CD   │                │ + ArgoCD CD   │                │ 灰度发布       │
│ (Python Demo) │                │ (Java Demo)   │                │ (依赖方案2)    │
└───────┬───────┘                └───────┬───────┘                └───────┬───────┘
        │                                │                                │
        └────────────────────────────────┼────────────────────────────────┘
                                         │ 全部部署到 K8s 集群
                                         ▼
        ┌─────────────────────────────────────────────────────────────────────┐
        │                        可观测性三大支柱 (可观测性)                │
        │  Metrics: Prometheus + AlertManager + NodeExporter                  │
        │  Logs:    Loki + Promtail                                          │
        │  Traces:  SkyWalking OAP + UI                                     │
        │  Panels:  Grafana (Dashboard JSON + 告警规则)                      │
        └─────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
        ┌─────────────────────────────────────────────────────────────────────┐
        │                    K8s 三基石 (集群基础能力)                          │
        │  HPA(弹性伸缩) + PV/PVC(持久化存储) + Ingress(外部流量入口)          │
        └─────────────────────────────────────────────────────────────────────┘
```

---

## 三套方案速览

| 方案 | CI 工具 | CD 工具 | 验证项目 | 适用场景 |
|------|--------|--------|---------|---------|
| [**方案1**](./方案1-Jenkins-ArgoCD/) | Jenkins | ArgoCD | SnowNLP 情感分析 (Python) | 已有 Jenkins 的团队 |
| [**方案2**](./方案2-GitLab-ArgoCD/) | GitLab CI | ArgoCD | Tomcat 应用 (Java) | 使用 GitLab 的团队 |
| [**方案3**](./方案3-Argo-Rollouts/) | 复用方案2 | Argo Rollouts | Tomcat 多环境灰度 | 需要金丝雀/蓝绿发布 |

> 📊 详细对比见 [三套方案对比](./CI-CD总览/CI-CD-GitOps-三套方案对比.md) | 🎓 生态工具面经见 [CICD 生态工具速览](./CI-CD总览/CICD生态工具速览-理论补充.md)

---

## 目录结构

```
项目实战/
│
├── README.md                            ← 📍 你在这里
│
├── 全局参考/                            ← 📖 全局文档
│   ├── 全局部署指南.md                  ← 🚀 从零部署全流程
│   └── 术语表.md                        ← 📖 K8s/DevOps 缩写速查
│
├── 部署工具/                            ← 🔧 环境变量 + 部署辅助脚本
│   ├── env.sh                           ← ⚙️ 统一环境变量（all-in-one）
│   ├── deploy-helper.sh                 ← 🔧 envsubst 模板渲染函数库
│   └── template-migrate.ps1             ← 🔄 YAML 硬编码 → ${VAR} 占位符
│
├── CI-CD总览/                           ← 📊 CI/CD 理论对比 + 面试速览
│   ├── CI-CD-GitOps-三套方案对比.md     ← 📊 三方案的架构/流程/选型指南
│   └── CICD生态工具速览-理论补充.md     ← 🎓 Argo 家族/GitHub Actions/Tekton 面试速览
│
├── K8s基础/                             ← 📝 K8s 核心能力
│   └── K8s-三基石-HPA-存储-Ingress.md   ← 📝 HPA/PVC/Ingress 实战 + 面试速答
│
├── 方案1-Jenkins-ArgoCD/               ← CI: Jenkins | Demo: Python/SnowNLP
│   ├── README.md                       ← 架构总览 + GitOps 流程图
│   ├── 关键配置详解.md
│   ├── 故障排查手册.md
│   ├── 端到端操作实录.md
│   ├── 项目结构对照.md
│   └── 配置文件/                        ← 所有可部署的 YAML/脚本
│
├── 方案2-GitLab-ArgoCD/                ← CI: GitLab Runner | Demo: Java/Tomcat
│   ├── README.md
│   ├── 关键配置详解.md
│   ├── 故障排查手册.md
│   ├── 端到端操作实录.md
│   ├── 项目结构对照.md
│   └── 配置文件/                        ← GitLab + Runner + ArgoCD Application
│
├── 方案3-Argo-Rollouts/                ← CD: 金丝雀+蓝绿 | 依赖方案2的仓库
│   ├── README.md
│   ├── 故障排查手册.md
│   ├── 端到端操作实录.md
│   ├── 01-install-rollouts.sh
│   ├── 02-apply-rollouts.sh
│   ├── k8s/                            ← Rollout 定义 (base + overlays)
│   └── argocd/                         ← ArgoCD Application (3 环境)
│
├── 可观测性/                            ← 可观测性三大支柱 + 增强 (三方案共用)
│   ├── 可观测性三大支柱-操作留痕与排障手册.md
│   ├── 可观测性三大支柱-改进报告.md
│   ├── 01-metrics/                    ← Prometheus 指标采集
│   │   └── servicemonitor/            ← ServiceMonitor 改造 (28 targets ALL UP)
│   ├── 02-logs/                       ← Loki 日志聚合
│   │   ├── log-alerting/              ← 日志分级告警 (3 条规则)
│   │   └── loki-multitenant/          ← 多租户隔离
│   ├── 03-traces/                     ← SkyWalking 链路追踪
│   │   └── agent/                     ← Java Agent 无侵入注入
│   ├── 04-es-storage/                 ← ES 3 节点集群 (追踪存储后端)
│   ├── monitoring-ingress.yaml        ← 4 路由 + TLS + basic-auth
│   └── ...
│
├── eBPF-可观测性/                      ← eBPF 可观测性 (Cilium 接管 CNI + Hubble 流量观测)
├── CNI总览/                            ← Calico vs Cilium 生产配置对比（选型决策参考）
├── Calico-配置指南/                    ← Calico 生产配置详解 + 故障排查（作 Cilium 回退备援资料）
├── 流量入口/                            ← Ingress 暴露 + cert-manager TLS + Gateway API 金丝雀
├── 密钥管理/                            ← Sealed Secrets 加密凭据落地
├── 镜像仓库/                            ← Harbor 自动清理策略
├── 存储管理/                            ← NFS Provisioner 动态存储供给
├── 弹性伸缩/                            ← KEDA Cron 定时伸缩
├── HiAgent/                             ← HiAgent 私有化部署运维实战
├── 工作日志/                            ← 📝 日志(按日期归档) + 待办清单(进度/规划)
└── 外网资源同步/                         ← 🌐 US→H1→Harbor 镜像/资料同步（脚本+手册）
```

---

## 核心设计理念

### GitOps：Git 是唯一真相源

> CI 不直接操作 K8s（不用 `kubectl apply`），而是 **修改 Git 中的 YAML 清单**，让 ArgoCD 自动检测并同步。

```
开发者 Push 代码 → CI 构建镜像 → 推送 Harbor → 更新 Git 中 YAML → ArgoCD 自动同步到 K8s
```

### 参数化配置：换集群只改一个文件

所有 YAML 中的可变值（Harbor IP、域名、StorageClass、NodePort）都通过 `${变量}` 占位符引用，由 `env.sh` 统一管理。部署时 `deploy-helper.sh` 自动完成 `envsubst` 模板渲染。

> 📝 修改 `env.sh` → `source env.sh` → 运行一键脚本 → 全链路自动适配新环境

---

## 快速开始（最快 15 分钟）

```bash
# 1. 修改环境配置
cp 部署工具/env.sh env.local.sh
vim env.local.sh    # 改 HARBOR_IP, HARBOR_PASS, STORAGE_CLASS 等
source env.local.sh

# 2. 创建命名空间
for ns in monitoring argocd jenkins git gitlab tomcat-demo tomcat-dev tomcat-staging tomcat-prod; do
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
done

# 3. 部署方案1 (Jenkins + ArgoCD) — 当前环境就绪度最高
cd 方案1-Jenkins-ArgoCD/配置文件/scripts/
bash one-click-init.sh

# 4. 部署监控栈
cd ../../../可观测性/
source ../env.local.sh
bash restore-monitoring.sh    # 从备份快照恢复，或 kubectl apply -f argocd/application.yaml
```

> 📖 完整步骤见 [全局部署指南.md](./全局参考/全局部署指南.md)

---

## 技术栈一览

| 分类 | 组件 | 在本项目中的作用 |
|------|------|----------------|
| **镜像仓库** | Harbor | 内网 Docker 镜像存储，含 Trivy 漏洞扫描 + 自动清理策略 |
| **CI** | Jenkins / GitLab CI | 代码构建 → 推送镜像 → 更新 Git YAML |
| **CD** | ArgoCD | 自动检测 Git 变更 → 同步到 K8s 集群 |
| **灰度发布** | Argo Rollouts | 金丝雀(Canary) + 蓝绿(BlueGreen) 发布策略 |
| **配置管理** | Kustomize | base + overlays 多环境配置复用 |
| **密钥管理** | Sealed Secrets | kubeseal 加密 Harbor 凭据 → 自动解密 → Pod 注入 ✅ |
| **证书管理** | cert-manager | 自签 CA → ClusterIssuer → TLS 证书自动颁发 ✅ |
| **指标监控** | Prometheus + Grafana | 28 targets ALL UP + Cluster Overview Dashboard + 告警规则 |
| **日志采集** | Loki + Promtail | 容器日志聚合搜索，trace_id 关联，多租户隔离 ✅ |
| **链路追踪** | SkyWalking | 服务拓扑 + 调用链 + Java Agent 无侵入注入 ✅ |
| **弹性伸缩** | KEDA + HPA | Cron 定时伸缩 + CPU 指标伸缩 ✅ |
| **搜索存储** | Elasticsearch 3 节点集群 | SkyWalking 后端存储，Green 状态 2 索引含副本 ✅ |
| **持久存储** | NFS Provisioner | 动态 PV 供给，ReadWriteMany，自建 watch loop ✅ |
| **流量入口** | nginx-ingress + Gateway API | 域名路由 + TLS + 金丝雀权重分流 ✅ |
| **eBPF 可观测性** | Cilium + Hubble | eBPF 接管 CNI(VXLAN) + Hubble 流量/DNS 可观测 + Grafana eBPF Dashboard ✅ |
| **证书安全** | cert-manager | 自签 CA → ClusterIssuer → 4 SAN 域名 TLS ✅ |

---

## 相关资源

| 文档 | 说明 |
|------|------|
| [术语表.md](./全局参考/术语表.md) | K8s/DevOps 常见缩写和概念解释 |
| [全局部署指南.md](./全局参考/全局部署指南.md) | 从零到全链路跑通的完整步骤 |
| [CI-CD-GitOps-三套方案对比.md](./CI-CD总览/CI-CD-GitOps-三套方案对比.md) | 三套方案的架构图和对比表格 |
| [CICD生态工具速览-理论补充.md](./CI-CD总览/CICD生态工具速览-理论补充.md) | Argo 家族、GitHub Actions 等面试补充 |
| [K8s-三基石-HPA-存储-Ingress.md](./K8s基础/K8s-三基石-HPA-存储-Ingress.md) | HPA/PVC/Ingress 实战笔记 + 面试速答 |
| [外网资源同步/](./外网资源同步/) | US→H1→内网：镜像同步 + 外网文件下载 完整工作流 |

---

## 项目状态

- ✅ **CI/CD 三方案** — Jenkins/GitLab CI + ArgoCD，全部可部署
- ✅ **灰度发布** — Argo Rollouts Canary + BlueGreen
- ✅ **可观测性** — Prometheus/Grafana/Loki/SkyWalking 完整配置 + 集群运行中
- ✅ **K8s 三基石** — HPA/PVC/Ingress 已落地验证
- ✅ **密钥管理** — Sealed Secrets 实操验证 (kubeseal 加密 → 自动解密)
- ✅ **证书管理** — cert-manager 自签 CA + 4 SAN 域名 TLS
- ✅ **Skywalking Agent** — Java Agent hostPath 注入 + 全链路追踪
- ✅ **ServiceMonitor** — Prometheus Operator 改造，28 targets ALL UP
- ✅ **日志告警** — Loki Ruler 3 条告警规则 (高错误率/Java异常/OOMKill)
- ✅ **Harbor 清理** — Retention Policy + GC 每日凌晨 3:00
- ✅ **NFS Provisioner** — 自建动态供给，3 个 PVC 已绑定
- ✅ **KEDA** — 事件驱动伸缩，Cron ScaledObject 工作日 9-18 扩缩
- ✅ **Gateway API** — Envoy Gateway v1.2.0，80/20 金丝雀流量分割
- ✅ **ES 集群** — 3 节点 StatefulSet，GREEN，含副本分片
- ✅ **Loki 多租户** — auth_enabled + tenant_id + X-Scope-OrgID 隔离
- ⏳ **Master 加内存** — 运维层面（P2c.10）
- ✅ **eBPF 可观测性** — Cilium 接管 CNI(VXLAN) + Hubble 流量/DNS 可观测 + Grafana eBPF Dashboard（详见 `eBPF-可观测性/`）
- ✅ **CNI 双资料** — Cilium 生产配置指南(含跨节点实测) + Calico 生产配置指南 + CNI 总览对比（详见 `eBPF-可观测性/Cilium-生产配置指南.md`、`Calico-配置指南/`、`CNI总览/`）
📋 **长期任务** — OpenTelemetry / Chaos Mesh / Kyverno（eBPF 已完成）
