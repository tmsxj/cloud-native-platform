# 长期19 — Kyverno（策略即代码引擎） 策略即代码（Policy-as-Code）

> 📅 完成: 2026-07-09 | 状态: ✅ 已部署（`kyverno` 命名空间，worker 限定）| 验证: `disallow-latest-tag` + `restrict-image-registries` 实测拒绝违规 Pod（容器组），合规 Pod 正常准入
> 配套安全基线: 替代「人工检查镜像标签/来源」，把安全合规规则沉淀为版本化、可审计、自动拦截的代码

## 1. 这是什么 / 为什么做

**Kyverno** 是 CNCF 毕业级、K8s 原生的**策略引擎**（Policy-as-Code）。它用 CRD（`ClusterPolicy`）描述准入控制规则，作为 **Validating/Mutating Admission Webhook（准入/回调钩子）** 在 Pod 创建/更新时自动校验或改写。

本项目做它的目的：
- **替代"人工镜像检查"**：以前靠人肉 review 镜像是否用 `:latest`、是否来自可信源；现在用策略**自动、强制、零遗漏**地拦截
- 补齐 `可观测性 / eBPF（内核可编程技术） / 混沌工程` 之后的**安全准入**一环——"能观测、能抗故障、还能挡违规"
- 面试亮点：能讲清"安全合规基线我用代码声明、自动执行，而不是靠文档和人工"

## 2. 架构

```
┌─────────────────────────────────────────────────────────────┐
│  kyverno 命名空间（★仅 worker1/worker2★，master 不调度）       │
│                                                               │
│  kyverno-admission-controller  (Deployment, 单副本)           │
│     │  作为 Validating Webhook 拦截 API Server 的 create/update│
│     ▼                                                         │
│  kyverno-background-controller (Deployment, 单副本)           │
│     │  后台扫描已有资源 / 生成 PolicyReport                     │
│     ▼                                                         │
│  kyverno-cleanup-controller / reports-controller (单副本)     │
└─────────────────────────────────────────────────────────────┘
        ▲ 拦截 create/update
        │
   API Server ──► 业务 Pod（tomcat-demo / otel-demo 等）
        │
   规则来源 = policies/*.yaml（ClusterPolicy，版本化进 Git）
```

### 为什么只跑 worker？
master 每节点仅 2.5G（占用 75–86%），而 Kyverno 本身是常驻控制面。给 `worker1/worker2` 打标签 `kyverno-scope=true`，用顶层 `nodeSelector` 限定全部组件只调度到 worker；master 自带 `control-plane:NoSchedule` 污点且我们显式 `tolerations: []`，双重保险不会落 master。详见 `values-worker-scoped.yaml`。

## 3. 部署

```bash
# 在 m1 上（KUBECONFIG=/etc/kubernetes/admin.conf）
bash deploy.sh
```

`deploy.sh` 做了：
1. 加 helm repo（kyverno.github.io/kyverno）
2. 建 `kyverno` 命名空间，给 worker 打 `kyverno-scope=true` 标签
3. `helm upgrade --install kyverno kyverno/kyverno -n kyverno -f values-worker-scoped.yaml --version 3.8.1`
4. 等待 Pod Running 后，批量 `kubectl apply -f policies/`

> ⚠️ **镜像来源**：Kyverno 镜像来自 `ghcr.io/kyverno/*`（集群出网已放行 ghcr.io，可达）。无需 Harbor（私有镜像仓库） 同步。

> ⚠️ **v1.18 兼容性踩坑（实测）**：本项目集群的 apiserver 版本较旧，Kyverno v1.18.1 踩了两个坑：
> 1. **API group 改名**：CRD（自定义资源定义） 实际 group 已是 `kyverno.io`（旧文档/老版本是 `policies.kyverno.io`）。策略必须写 `apiVersion: kyverno.io/v1`，否则 `kubectl apply` 报 "no matches for kind ClusterPolicy in version policies.kyverno.io/v1"。
> 2. **`spec.exclude` 已移除**：v1.18 删掉了顶层 `spec.exclude`，排除逻辑必须放到**每条 rule 内部**的 `rules[].exclude`（顶层写会报 "unknown field spec.exclude"）。
> 安装时 chart 还会对 CRD 报 `unknown field spec.versions[].selectableFields` 的 warning（旧 apiserver 不认识该字段），但 CRD 仍能正常创建，无害，可忽略。

## 4. 已落地策略（见 `policies/`）

> 全部 `validationFailureAction: Enforce`（违规直接拒绝准入），并 `exclude` 掉 kube-system/kyverno 等系统命名空间避免误伤。

| 策略 | 作用 | 对应"人工检查"替代 |
|------|------|-------------------|
| `disallow-latest-tag` | 禁止镜像使用 `:latest` 标签 | 替代"人工核对镜像是否固定版本" |
| `restrict-image-registries` | 仅允许 `192.168.1.61:5000`(Harbor) 与 `ghcr.io` | 替代"人工核对镜像来源"，并规避 docker.io 不可达 |
| `require-probes` | 容器必须配置 liveness/readiness 探针 | 替代"人工核对健康检查配置" |
| `disallow-privileged` | 禁止 `privileged: true` 容器 | 替代"人工核对安全上下文" |

## 5. 验证（见 `verify.sh`）

```bash
bash verify.sh
```

实测结果：
- **违规 Pod**（`image: nginx:latest`，来自 docker.io）→ 被 `disallow-latest-tag` 与 `restrict-image-registries` 双重拒绝，API Server 返回明确拒绝原因
- **合规 Pod**（`ghcr.io/kyverno/kyverno:v1.18.1` + 探针）→ 正常准入创建

这证明：**策略即代码已真正在准入链路生效，替代了人工镜像检查**。

> 💡 安全提示：Kyverno 故障（webhook 不可达）默认 `failurePolicy: Fail` 会阻断全集群准入。演示环境请保持 Kyverno 运行；生产可评估改为 `Ignore` 或保证 HA。

## 6. 卸载

```bash
kubectl delete -f policies/
helm -n kyverno uninstall kyverno
kubectl delete namespace kyverno
```

## 7. 面试要点

- **Policy-as-Code**：把安全/合规基线写成声明式 YAML，进 Git 版本管理、可 review、可回滚、可审计——远比人工检查可靠
- **准入控制（Admission Control）** 是 K8s（Kubernetes，容器编排引擎） 安全最后一道闸：Kyverno 作为 Validating/Mutating Webhook 在资源落库前拦截
- 与 OPA（Open Policy Agent，策略引擎）/Gatekeeper 的区别：Kyverno **纯 YAML、无需学新语言（Rego）**，K8s 原生体验更好，适合团队快速落地
- 本项目四条策略覆盖了"镜像标签 / 镜像来源 / 健康检查 / 安全上下文"四个最常被人工 review 的合规点
