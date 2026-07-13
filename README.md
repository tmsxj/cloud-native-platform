# 项目实战：K8s 全链路 CI/CD（持续集成/持续交付） + 可观测性 + 灰度发布

> 基于自建 5 节点 kubeadm 集群的 DevOps 实战项目，覆盖 **CI/CD 三方案 → 可观测性三大支柱 → 灰度发布 → K8s 三基石 → 服务网格双栈 → 供应链安全** 全链路，并收敛为完整 **DevSecOps 四层闭环**（扫描 Trivy + 准入 Kyverno（策略即代码引擎） + 运行时 Falco + 供应链验签）。
>
> 📅 最近更新: 2026-07-12 | 状态: P0~P2b + 长期16~19 全部完成 ✅ | 后续增强 20 可靠性保障 ✅ / 21 Velero 备份容灾 ✅ / 22 Falco 运行时安全 ✅ / 23 服务网格·Linkerd ✅ + Istio ✅(双网格对比演示完成) / 24 供应链安全 ✅(cosign 签名 + Kyverno verifyImages 验签 + SBOM) / 25 密钥进阶 ✅(Vault + External Secrets Operator（外部密钥操作符，ESO） 自动同步 K8s Secret) | 🔒 聚焦模式已激活（全家桶冻结，专攻 23~31）
>
> 📡 同步镜像: 本仓库同时托管于 GitHub 与 Gitee（[hlxb/cloud-native-platform](https://gitee.com/hlxb/cloud-native-platform)），`git push` 自动双推，两端内容一致。目标实操环境：自建 kubeadm 5 节点离线集群（Cilium/Hubble eBPF 数据面 + Linkerd（服务网格）/Istio 双服务网格）。
>
> 🗺️ **想按体系化顺序系统学习？看 [学习路线.md](./学习路线.md)（按能力递进的观看顺序，目录结构不变）。**

---

## 这是什么？

一套完整的 K8s DevOps 落地工程，从零搭建了 **Harbor(镜像仓库) + Jenkins/GitLab CI(持续集成) + ArgoCD(GitOps 持续部署) + Prometheus/Grafana/Loki(S3)/OpenTelemetry（OTel，可观测性数据采集标准）+Tempo(LGTM 全栈 S3 化)(可观测性) + Argo Rollouts(灰度发布)**。

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
        │  Logs:    Loki(S3/MinIO 对象存储) + Promtail                       │
        │  Traces:  OpenTelemetry Collector + Tempo(S3/MinIO 对象存储, 对齐 LGTM)  │
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
| [**方案2**](./方案2-GitLab（代码托管 + CI 平台）-ArgoCD/) | GitLab CI | ArgoCD | Tomcat 应用 (Java) | 使用 GitLab 的团队 |
| [**方案3**](./方案3-Argo-Rollouts/) | 复用方案2 | Argo Rollouts（渐进式发布控制器） | Tomcat 多环境灰度 | 需要金丝雀/蓝绿发布 |

> 📊 详细对比见 [三套方案对比](./CI-CD总览/CI-CD-GitOps（以 Git 为唯一真相源的运维模式）-三套方案对比.md) | 🎓 生态工具面经见 [CICD 生态工具速览](./CI-CD总览/CICD生态工具速览-理论补充.md)

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
│   ├── 03-traces/                     ← SkyWalking 链路追踪（方案 A，manifest 保留；05-otel 为方案 B 当前运行）
│   │   └── agent/                     ← Java Agent 无侵入注入
│   ├── 04-es-storage/                 ← ES 3 节点集群（已卸载，追踪存储改 Tempo 对象存储）
│   ├── 05-otel/                       ← ✅ OpenTelemetry + LGTM(Tempo+MinIO) 链路追踪（替换 SkyWalking+ES）
│   │   ├── README.md                  ← 替换背景/架构(LGTM)/部署/验证/卸载/接入全流程
│   │   ├── minio.yaml                 ← MinIO 对象存储（Tempo 的 S3 后端）
│   │   ├── tempo.yaml                 ← Grafana Tempo 单体(3.0)：OTLP receiver + S3 存储
│   │   ├── otel-collector.yaml        ← OTel Collector 收口网关（:4317/4318 → Tempo）
│   │   ├── otel-demo-app.yaml         ← 演示应用（裸 OTLP/JSON 投递 trace）
│   │   ├── jaeger.yaml                ← ⚠️ 历史参考：早期 Jaeger 内存版（已弃用）
│   │   └── _grafana-datasources.yaml  ← Grafana 预置数据源 CM（含 Tempo）
│   ├── monitoring-ingress.yaml        ← 3 路由 + TLS + basic-auth（已移除 skywalking.lab.local）
│   └── ...
│
├── eBPF-可观测性/                      ← eBPF 可观测性 (Cilium 接管 CNI + Hubble 流量观测)
├── 混沌工程-ChaosMesh/                   ← Chaos Mesh 混沌工程（worker 限定，注入故障验证韧性）
├── 策略即代码-Kyverno/                   ← Kyverno 策略即代码（准入控制，替代人工镜像检查）
├── 可靠性保障/                          ← PDB/ResourceQuota/LimitRange/PriorityClass 防御性配置（详见 `可靠性保障/`）✅
├── 备份容灾/                            ← Velero + MinIO(S3) 备份/恢复容灾，闭环已验证（详见 `备份容灾/`）✅
├── 运行时安全/                          ← Falco 运行时安全（DaemonSet + modern_ebpf，离线容器级富化，详见 `运行时安全/Falco/`）✅
├── 服务网格/                            ← 第23项 服务网格（双网格对比演示）：`Linkerd/` + `Istio/` 均已离线落地并验证（mTLS+黄金指标+流量治理/熔断）；控制面限定 worker，详见 deploy-linkerd.md / deploy-istio.md / 服务网格对比-Linkerd-vs-Istio.md
├── 供应链安全/                          ← 第24项 供应链安全：cosign 镜像签名 + syft 生成 SBOM + Kyverno verifyImages 验签闭环（签名放行/未签名拒绝已验证，详见 `供应链安全/`）✅
├── 密钥进阶/                            ← 第25项 密钥进阶：Vault 集中密钥库 + External Secrets Operator 自动同步 K8s Secret（SecretStore/ExternalSecret 闭环已验证，详见 `密钥进阶/`）✅
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
| **镜像仓库** | Harbor（私有镜像仓库） | 内网 Docker 镜像存储，含 Trivy 漏洞扫描 + 自动清理策略 |
| **CI** | Jenkins / GitLab CI | 代码构建 → 推送镜像 → 更新 Git YAML |
| **CD** | ArgoCD | 自动检测 Git 变更 → 同步到 K8s（Kubernetes，容器编排引擎） 集群 |
| **灰度发布** | Argo Rollouts | 金丝雀(Canary) + 蓝绿(BlueGreen) 发布策略 |
| **配置管理** | Kustomize（K8s 清单定制工具） | base + overlays 多环境配置复用 |
| **密钥管理** | Sealed Secrets | kubeseal 加密 Harbor 凭据 → 自动解密 → Pod（容器组） 注入 ✅ |
| **证书管理** | cert-manager | 自签 CA → ClusterIssuer → TLS 证书自动颁发 ✅ |
| **指标监控** | Prometheus（指标监控系统） + Grafana | 28 targets ALL UP + Cluster Overview Dashboard + 告警规则 |
| **日志采集** | Loki（日志系统）(S3) + Promtail | 容器日志聚合搜索，trace_id 关联，多租户隔离；存储已切 MinIO(S3) ✅ |
| **链路追踪** | OpenTelemetry + Tempo(LGTM) | 标准 OTLP 收口（Collector :4317/4318）→ Tempo 单体(3.0) + MinIO(S3) 对象存储；Grafana（可视化面板） 接 Tempo 数据源 ✅ |
| **弹性伸缩** | KEDA（基于事件的自动伸缩） + HPA | Cron 定时伸缩 + CPU 指标伸缩 ✅ |
| **搜索存储** | Elasticsearch 3 节点集群 | ❌ 已卸载（2026-07-09）：trace 存储改 Tempo（链路追踪后端）(对象存储)，释放 ~6Gi local-path + worker 内存 |
| **持久存储** | NFS Provisioner | 动态 PV 供给，ReadWriteMany，自建 watch loop ✅ |
| **流量入口** | nginx-ingress + Gateway API（网关 API，Ingress 继任标准） | 域名路由 + TLS + 金丝雀权重分流 ✅ |
| **eBPF 可观测性** | Cilium（基于 eBPF 的 CNI/网络方案） + Hubble | eBPF 接管 CNI(VXLAN) + Hubble 流量/DNS 可观测 + Grafana eBPF Dashboard ✅ |
| **混沌工程** | Chaos Mesh | PodChaos/NetworkChaos/StressChaos 注入故障验证系统韧性（详见 `混沌工程-ChaosMesh（混沌工程工具）/`）✅ |
| **策略即代码** | Kyverno | 准入控制：禁 latest 标签 / 限可信仓库 / 要求探针 / 禁特权，替代人工镜像检查（详见 `策略即代码-Kyverno/`）✅ |
| **可靠性保障** | PDB / ResourceQuota / LimitRange / PriorityClass | 防御性配置：可用性/驱逐安全(PDB) + 资源治理(Quota/LimitRange) + 优雅优先级(PriorityClass)（详见 `可靠性保障/`）✅ |
| **备份容灾** | Velero（备份容灾工具） + MinIO(S3) | 集群级备份/恢复，复用现有 MinIO 对象存储作 S3 后端；备份+恢复闭环已验证（详见 `备份容灾/`）✅ |
| **运行时安全** | Falco（运行时安全检测） (modern_ebpf) | 运行时威胁检测：异常进程/提权/敏感文件读取，镜像内置容器插件离线做容器级富化（DevSecOps 三层收尾，详见 `运行时安全/Falco/`）✅ |
| **供应链安全** | cosign（镜像签名工具） + syft + Kyverno verifyImages | 镜像签名（本地私钥）+ SBOM 生成 + 准入验签（未签名一律拒绝），DevSecOps 第四层闭环（详见 `供应链安全/`）✅ |
| **密钥进阶** | Vault + External Secrets Operator（操作符，自动化运维控制器） | 集中密钥管理（Vault KV v2）+ 自动同步为 K8s Secret（SecretStore/ExternalSecret），应用无感知使用动态密钥，DevSecOps 密钥管理层（详见 `密钥进阶/`）✅ |
| **证书安全** | cert-manager | 自签 CA → ClusterIssuer → 4 SAN 域名 TLS ✅ |

---

## 相关资源

| 文档 | 说明 |
|------|------|
| [术语表.md](./全局参考/术语表.md) | K8s/DevOps 常见缩写和概念解释 |
| [全局部署指南.md](./全局参考/全局部署指南.md) | 从零到全链路跑通的完整步骤 |
| [CI-CD-GitOps-三套方案对比.md](./CI-CD总览/CI-CD-GitOps-三套方案对比.md) | 三套方案的架构图和对比表格 |
| [CICD生态工具速览-理论补充.md](./CI-CD总览/CICD生态工具速览-理论补充.md) | Argo 家族、GitHub Actions 等面试补充 |
| [K8s-三基石-HPA（水平 Pod 伸缩）-存储-Ingress.md](./K8s基础/K8s-三基石-HPA-存储-Ingress.md) | HPA/PVC/Ingress 实战笔记 + 面试速答 |
| [外网资源同步/](./外网资源同步/) | US→H1→内网：镜像同步 + 外网文件下载 完整工作流 |

---

## 项目状态

- ✅ **CI/CD 三方案** — Jenkins/GitLab CI + ArgoCD，全部可部署
- ✅ **灰度发布** — Argo Rollouts Canary + BlueGreen
- ✅ **可观测性** — Prometheus/Grafana/Loki 完整配置 + 集群运行中；**traces 已升级为 OpenTelemetry + Tempo(LGTM)（替换原 SkyWalking（APM 调用链追踪）+ES）**，**Loki 存储也已切到 MinIO(S3) 实现 LGTM 全栈 S3 化**（详见 `可观测性/05-otel/`）
- ✅ **K8s 三基石** — HPA/PVC/Ingress 已落地验证
- ✅ **密钥管理** — Sealed Secrets 实操验证 (kubeseal 加密 → 自动解密)
- ✅ **证书管理** — cert-manager 自签 CA + 4 SAN 域名 TLS
- ✅ **Skywalking Agent** — Java Agent hostPath 注入 + 全链路追踪
- ✅ **ServiceMonitor** — Prometheus Operator 改造，28 targets ALL UP
- ✅ **日志告警** — Loki Ruler 3 条告警规则 (高错误率/Java异常/OOMKill)
- ✅ **Harbor 清理** — Retention Policy + GC 每日凌晨 3:00
- ✅ **NFS Provisioner** — 自建动态供给，3 个 PVC 已绑定
- ✅ **KEDA** — 事件驱动伸缩，Cron ScaledObject 工作日 9-18 扩缩
- ✅ **Gateway（网关实例） API** — Envoy Gateway v1.2.0，80/20 金丝雀流量分割
- ❌ **ES 集群** — 已卸载（2026-07-09）：SkyWalking 链路追踪改由 Tempo(对象存储) 承接，ES 三节点 StatefulSet（有状态工作负载） + PVC 全部删除，释放 worker 内存
- ✅ **Loki 多租户** — auth_enabled + tenant_id + X-Scope-OrgID 隔离
- ⏳ **Master 加内存** — 运维层面（P2c.10）
- ✅ **eBPF（内核可编程技术） 可观测性** — Cilium 接管 CNI(VXLAN) + Hubble 流量/DNS 可观测 + Grafana eBPF Dashboard（详见 `eBPF-可观测性/`）
- ✅ **CNI 双资料** — Cilium 生产配置指南(含跨节点实测) + Calico（CNI/网络策略方案） 生产配置指南 + CNI 总览对比（详见 `eBPF-可观测性/Cilium-生产配置指南.md`、`Calico-配置指南/`、`CNI总览/`）
- ✅ **Chaos Mesh 混沌工程** — chaos-testing 命名空间已部署（worker 限定，master 不跑 daemon）；PodChaos 实测注入并重建目标 Pod（详见 `混沌工程-ChaosMesh/`）
- ✅ **Kyverno 策略即代码** — kyverno 命名空间已部署（worker 限定）；4 条策略（禁 latest 标签 / 限可信仓库 / 要求探针 / 禁特权）实测拦截违规 Pod、放行合规 Pod（详见 `策略即代码-Kyverno/`）
- ✅ **可靠性保障套件** — 2 个 PriorityClass + LimitRange + ResourceQuota + PDB(minAvailable=2) 已落地并验证；demo 3 副本 Running 于 worker（详见 `可靠性保障/`）✅
- ✅ **Velero 备份容灾** — velero 命名空间已部署（复用 monitoring 的 MinIO S3 后端）；备份+恢复闭环实测 Completed(0 error)（详见 `备份容灾/`）✅
- ✅ **Falco 运行时安全** — falco DaemonSet（守护进程集） 仅落 worker（master NoSchedule 挡住）；modern_ebpf + 镜像内置容器插件离线富化；`cat /etc/shadow` 触发 Warning 告警含 container/pod/ns 元信息（详见 `运行时安全/Falco/`）✅
- ✅ **供应链安全（第24项）** — cosign 本地私钥签名镜像 + syft 生成 SBOM；Kyverno verifyImages 策略（`imageReferences=192.168.1.61:5000/*`，keys 公钥验签 + `rekor.ignoreTlog`/`ctlog.ignoreSCT` 跳过透明日志适配离线）实测：签名镜像放行、未签名镜像被拒（`no signatures found`），DevSecOps 第四层（扫描 Trivy（镜像漏洞扫描） + 准入 Kyverno + 运行时 Falco + 供应链验签）闭环成立（详见 `供应链安全/`）✅
📋 **后续增强路线（云原生能力补全 20~31）** — ✅ 20 可靠性保障已完成 / ✅ 21 Velero 备份容灾已完成 / ✅ 22 Falco 运行时安全已完成 / 🟢 23 服务网格已完成（**Linkerd ✅ + Istio（服务网格） ✅** 双网格对比演示：mTLS(STRICT)+黄金指标+流量治理/熔断全部验证，文档见 服务网格/）/ ✅ 24 供应链安全已完成 / ✅ 25 密钥进阶已完成（Vault+ESO 闭环）/ 🔭 **26~31 已规划为后续研究方向（短期内不做，详见 `增强路线26-31规划.md`）**：26 多集群与联邦治理 / 27 事件驱动弹性 KEDA / 28 Gateway API 标准化 / 29 K8s 排障与性能调优 / 30 SLO 工程与告警降噪 / 31 GitOps 进阶与渐进式交付深化 | 主线任务全部完成 ✅
