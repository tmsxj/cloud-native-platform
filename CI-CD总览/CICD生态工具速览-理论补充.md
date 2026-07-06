# CI/CD 生态工具速览（理论补充）

> 基于已落地的三套方案（Jenkins / GitLab CI / ArgoCD Rollouts），补充你可能没实际用过但面试会提到的工具。

---

## 一、已覆盖的（不用看）

| 工具 | 在你方案中的作用 |
|------|----------------|
| Jenkins | CI 引擎（方案1） |
| GitLab CI | SCM 集成的 CI 引擎（方案2） |
| ArgoCD | GitOps CD，自动同步 Git→K8s（三方案共用） |
| Argo Rollouts | 金丝雀 + 蓝绿发布策略（方案3） |
| Kustomize | 多环境配置管理（base + overlays） |
| Harbor | 私有 Docker 镜像仓库 |
| Prometheus + Grafana + Loki | 可观测性三件套 |

---

## 二、ArgoCD 生态内的兄弟工具

### 2.1 ArgoCD Image Updater

**你的方案3 已经在用。**

```
作用：自动检测 Harbor 中镜像 tag 变化 → 自动更新 Git 仓库或直接更新 K8s 资源
不用人手动改 kustomization.yaml 的 newTag 了。
```

**一句话讲它**："它是 ArgoCD 的'无人值守发布插件'，新镜像推到 Harbor 后自动触发 ArgoCD 同步。"

### 2.2 Argo Workflows

**你没用，但它是 Argo 家族老三。**

```
Argo CD        → 声明式 GitOps 部署（你用到了）
Argo Rollouts  → 渐进式发布（你用到了）
Argo Workflows → K8s 原生任务编排（你没用到）
Argo Events    → 事件驱动触发 Workflows
```

**它干什么的**：跑一次性任务，比如"每天凌晨2点清理旧镜像"、"部署前跑一套 E2E 测试"。Jenkins 也能干这事，但 Argo Workflows 每个步骤跑在一个独立 Pod 里，隔离性更好。

**面试说法**："我们 CI 阶段用 Jenkins/GitLab CI 做构建，如果有复杂的批量任务会考虑 Argo Workflows，但目前 Jenkins Pipeline 能满足需求。"

### 2.3 Argo Events

依赖外部事件触发 Workflows 或 Pipeline。比如："GitHub Webhook → Argo Events → Argo Workflows → 跑测试"。如果已经有 Jenkins 或 GitLab CI，这个不是必需品。

---

## 三、ArgoCD 的竞品

### 3.1 Flux CD

**ArgoCD 的头号竞品，纯 GitOps 领域只有这俩主流。**

| | ArgoCD | Flux CD |
|---|--------|---------|
| 理念 | Pull 模式，有 UI 面板 | Pull 模式，更偏 CLI |
| 配置 | Application CRD | GitRepository + Kustomization CRD |
| 多租户 | AppProject | 命名空间隔离 |
| 镜像自动更新 | Image Updater 插件 | 内置 ImageRepository API |
| 学习曲线 | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| 社区体量 | CNCF 毕业项目 | CNCF 毕业项目 |

**关键区别**：Flux 把"镜像检测更新"功能内置了（不需要额外装插件），但配置比 ArgoCD 更繁琐。ArgoCD 的 Web UI 是企业用户比较喜欢的点。

**面试说法**："我们选 ArgoCD 是因为它有直观的 Web 面板，方便团队可视化查看同步状态和 diff 变更。Flux 更 CLI 化，运维友好但团队协作上略逊一筹。"

---

## 四、CI 阶段你可能没接触的

### 4.1 GitHub Actions / Gitea Actions

**你的方案1 用了 Jenkins，方案2 用了 GitLab CI，这两的等价物还有 GitHub Actions。**

```
Jenkins      → 自建，Groovy 脚本，最灵活
GitLab CI    → 自托管/SaaS，.gitlab-ci.yml
GitHub Actions → SaaS，.github/workflows/*.yml
Gitea Actions → 自建轻量版（你内网的 Gitea 支持）
```

GitHub Actions 最大的特点是 **Marketplace 生态**，比如 `docker/build-push-action@v5` 一行就能替代你几十行手写的 build push 代码。

**面试说法**："如果代码托管在 GitHub，用 GitHub Actions 最省事；我们用的是内网 Gitea + GitLab，所以选了 Jenkins 和 GitLab CI。"

### 4.2 Tekton

**Kubernetes 原生的 CI 框架，被称作"CI 界的 Argo Workflows"。**

每个 CI 步骤（拉代码、构建、测试、推送）都跑在一个独立 Pod 里，跟 ArgoCD 天然兼容。

**为什么你没用到**：Tekton 上手成本高（Task → Pipeline → PipelineRun 三层抽象），Jenkinsfile 对大多数团队来说更直观。大厂用 Tekton 多，中小团队 Jenkins/GitLab CI 足够。

### 4.3 Kaniko / Buildpacks

**Docker-in-Docker（DinD）的替代方案。**

你的 Jenkins Pipeline 里很可能用的是 `docker build` + `docker push`，这需要 Jenkins 节点挂载 Docker socket（有安全风险）。

```
Kaniko    → 在容器里构建镜像，不需要 Docker Daemon
Buildpacks → 连 Dockerfile 都不用写，自动检测语言堆栈构建
```

**面试说法**："我们在 CI 中用 DinD 模式构建镜像，生产环境会考虑 Kaniko 替代以消除 Docker socket 挂载带来的安全风险。"

---

## 五、安全相关（面试容易问）

### 5.1 镜像漏洞扫描

**Harbor 已内置 Trivy 扫描，你的环境里配置过离线扫描 ✅**

```
你现有的链路:
  docker push → Harbor  → Trivy 自动扫描 → CVE 阻断策略（高危镜像禁止拉取）
```

Harbor 扫描 v.s. Pipeline 扫描的唯一区别：

| | Harbor 扫描（已配好） | Pipeline 扫描（未配） |
|---|---------------------|---------------------|
| 时机 | 推送后 | 推送前 |
| 优势 | 全局管控，统一策略 | "安全左移"，失败更早发现 |
| 必要性 | ⭐⭐⭐ 必需品 | ⭐ 锦上添花 |

**面试说法**："镜像安全通过 Harbor 离线 Trivy 扫描 + CVE 阻断策略实现，高危漏洞镜像直接禁止拉取。Pipeline 侧不需要重复扫描。"

### 5.2 Sealed Secrets / External Secrets / Vault

**你目前：K8s 原生 Secret（base64），内网环境。**

这道题的进化路径：

```
Level 1: kubectl create secret（base64 存 etcd）              ← 你现在
Level 2: Sealed Secrets — 加密后可安全提交 Git                  ← 最适合你
Level 3: External Secrets — 对接云厂商密钥管理（AWS/Azure/腾讯云）
Level 4: HashiCorp Vault — 完整密钥生命周期管理平台
```

**为什么 Level 2 最适合你？**
- Level 3 需要公有云凭据管理服务，有 API 计费，且依赖外部网络
- Sealed Secrets 纯 K8s 内闭环：加密用集群公钥 → 提交 Git → ArgoCD 同步 → 控制器自动解密
- 完全免费，不需要外部依赖

**云厂商方案用在哪**：公有云 K8s（EKS/AKS/TKE）+ AWS Secrets Manager / 腾讯云 SSM + External Secrets Operator。适合生产环境需要审计、轮转密钥的场景，但对内网自建集群性价比不高。

**面试说法**："内网集群用 K8s 原生 Secret，配合 ArgoCD 管理。如果 Git 仓库需要外传或合规要求，会引入 Sealed Secrets 实现加密提交，不依赖外部云服务。"

### 5.3 OPA / Kyverno — 策略即代码

**防止有人手贱 `kubectl delete namespace production`。**

```
OPA Gatekeeper → 通用策略引擎，Rego 语言
Kyverno        → K8s 原生策略，YAML 写规则
```

这是运维进阶话题，大多数场景 ArgoCD 的 `selfHeal: true` + RBAC 就够了。面试提到算加分项。

---

## 六、服务网格（跟方案3的金丝雀有交集）

### 6.1 Istio / Linkerd

**你的方案3 用 Argo Rollouts 实现金丝雀，流量切换是通过修改 Pod 标签 + Service Selector（第4层）。**

Istio 可以做到更细粒度——**第7层（HTTP header 级别）金丝雀**：

```
Argo Rollouts (你用的):
  "20% 流量去新版" → 靠 Pod 比例分配

Istio + Flagger:
  "User-Agent 包含 'mobile' 的请求全去新版" → 靠 Envoy 代理层实现
```

**面试说法**："当前用 Argo Rollouts 实现 Pod 级别的金丝雀和蓝绿发布，足以满足需求。如果需要 HTTP header 级别的流量切分，会引入 Istio + Flagger，但代价是每个 Pod 多一个 Envoy sidecar，增加运维开销。"

---

## 七、面试速记卡

| 面试问题 | 一句话回答 |
|----------|-----------|
| Helm 用过吗？ | 基础设施组件用 Helm，自己代码用 Kustomize overlays |
| ArgoCD 和 Flux 怎么选？ | ArgoCD 有 Web UI，团队可视化协作更好 |
| 镜像安全怎么做的？ | Harbor 离线 Trivy 扫描 + CVE 阻断策略，高危镜像禁止拉取 |
| 金丝雀怎么实现的？ | Argo Rollouts，DEV 用金丝雀 20%→100%，STAGING/PROD 用蓝绿 |
| Git 密钥能提交吗？ | 内网环境 K8s Secret，需外传时引入 Sealed Secrets 加密提交 |
| 云厂商密钥管理收费吗？ | 都按调用次数/凭据数量计费，内网自建集群 Sealed Secrets 更合适 |
| DinD 安全吗？ | 有风险，生产环境会替换为 Kaniko |
| Argo Workflows 用过吗？ | 了解，用于 K8s 原生任务编排，目前 Jenkins Pipeline 能满足 |
| 跟 K8s 原生 Rolling Update 比有什么区别？ | Argo Rollouts 多了手动审批、流量分析、自动回滚这些渐进发布能力 |
