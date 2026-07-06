# 方案一: Jenkins + ArgoCD GitOps 联动实施指南

> 适用场景: Jenkins 负责 CI (构建+测试+推送镜像), ArgoCD 负责 CD (GitOps 自动同步)

---

## 一、架构总览

```
                         ┌──────────────────────┐
                         │    开发者 Push 代码    │
                         └──────────┬───────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────┐
│                        Jenkins CI Pipeline                        │
│                                                                    │
│  Stage 1: git clone          拉取最新代码                          │
│  Stage 2: docker build       构建镜像 (tag=20260625-1300-42)       │
│  Stage 3: docker push        推送至 Harbor (192.168.1.61)         │
│  Stage 4: sed 替换标签       更新 deployment.yaml 中 image 行     │
│  Stage 5: git commit & push  提交变更 → 触发 ArgoCD 检测          │
│  Stage 6: wait sync          等待 ArgoCD 同步完成 (可选)          │
│                                                                    │
└───────────────────────────────┬──────────────────────────────────┘
                                │ git push 更新了 deployment.yaml
                                ▼
┌──────────────────────────────────────────────────────────────────┐
│                      ArgoCD (GitOps Engine)                        │
│                                                                    │
│  每 3min 检测 Git 变化 (可调至 30s)                                 │
│       │                                                            │
│       ▼ 检测到 deployment.yaml 变化                                │
│  ┌─────────────────────────────────────────────┐                  │
│  │  kubectl apply -f 01-app/deployment.yaml    │                  │
│  │  kubectl apply -f 01-app/service.yaml       │                  │
│  └─────────────────────────────────────────────┘                  │
│       │                                                            │
│       ▼                                                            │
│  ┌─────────────────────────────────────────────┐                  │
│  │       Kubernetes Cluster (monitoring)       │                  │
│  │  ┌─────────────────────────────┐            │                  │
│  │  │  snownlp-demo Deployment    │            │                  │
│  │  │  image: snownlp-demo:build-42│           │                  │
│  │  └─────────────────────────────┘            │                  │
│  └─────────────────────────────────────────────┘                  │
└──────────────────────────────────────────────────────────────────┘
```

**核心思想**: CI 不直接操作 K8s (`kubectl apply`)，而是**修改 Git 中的清单文件**，让 ArgoCD 自动检测并同步。Git = 唯一真相源。

---

## 二、环境信息

| 组件 | 地址 | 凭证 |
|------|------|------|
| **Jenkins** | `http://jenkins.test:31716` | 无登录 (Unsecured) |
| **ArgoCD** | `http://argocd.test:31716` | `admin` / `wRRzfFrgasxcpwwq` |
| **Harbor** | `192.168.1.61` | harbor-regcred (K8s Secret) |
| **Git 仓库** | `https://your-git-server/snownlp-observability-demo.git` | ⚠️ 部署时填写实际地址 |

---

## 三、前置准备

### 3.1 Git 仓库初始化

```powershell
# 进入 snownlp 项目目录
cd F:\项目管理2026\项目实战\snownlp-observability-demo

# 初始化 Git (如果还没有)
git init
git add .
git commit -m "init: snownlp demo with Jenkins + ArgoCD GitOps"

# 推送到远程仓库
git remote add origin https://your-git-server/snownlp-observability-demo.git
git push -u origin main
```

### 3.2 Jenkins 配置 Docker 权限

```bash
# 方法1: 把 Jenkins 容器/节点的用户加入 docker 组
usermod -aG docker jenkins

# 方法2: 修改 /var/run/docker.sock 权限 (简单但不安全)
chmod 666 /var/run/docker.sock
```

### 3.3 Jenkins 配置 Git 凭据 (如需)

Jenkins → Manage Jenkins → Credentials → System → Global credentials → Add Credentials:
- Kind: `Username with password` 或 `SSH Username with private key`
- ID: `git-credential-id` (与 Jenkinsfile 中对应)

### 3.4 Harbor Docker 登录 (在 Jenkins agent 上)

```bash
docker login 192.168.1.61 -u admin -p Harbor12345
# 如果是自签名证书:
# docker login 192.168.1.61 -u admin -p Harbor12345 --insecure-registry
```

### 3.5 安装 Jenkins 插件

Manage Jenkins → Plugins → Available plugins:
- `Docker Pipeline` — 在 Pipeline 中使用 docker 命令
- `Pipeline: Stage View` — 可视化 Stage 执行状态
- `Git` — Git 集成

---

## 四、部署步骤

### Step 1: 部署 ArgoCD Application

```powershell
# ⚠️ 先用实际 Git 地址替换 argocd/snownlp-demo-app.yaml 中的 repoURL

# 方式1: 通过 kubectl
kubectl apply -f argocd/snownlp-demo-app.yaml

# 方式2: 通过 ArgoCD CLI
argocd app create snownlp-demo \
  --project default \
  --repo https://your-git-server/snownlp-observability-demo.git \
  --path 01-app \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace monitoring \
  --sync-policy automated \
  --self-heal \
  --auto-prune \
  --insecure --grpc-web

# 当前集群状态 (已创建, 等 Git 仓库接入后自动同步):
#   snownlp-demo    → Unknown / Healthy (repo URL: 待替换)
#   monitoring-stack → Unknown / Healthy (repo URL: 待替换)
```

### Step 2: 在 Jenkins 创建 Pipeline Job

1. 打开 `http://jenkins.test:31716`
2. 左侧 **New Item** → 输入名称 `snownlp-demo-cicd` → 选择 **Pipeline**
3. Pipeline 定义 → 选择 **Pipeline script from SCM**
4. SCM: `Git`
5. Repository URL: `https://your-git-server/snownlp-observability-demo.git`
6. Branch: `*/main`
7. Script Path: `Jenkinsfile`
8. 点击 **Save**

### Step 3: 首次手动触发

1. 进入 `snownlp-demo-cicd` Job
2. 点 **Build Now**
3. 观察 6 个 Stage 执行:
   ```
   [Checkout]            → 拉取代码
   [Build Image]         → docker build -t snownlp-demo:20260625-1300-1
   [Push Image]          → docker push 192.168.1.61/monitoring/snownlp-demo:20260625-1300-1
   [Update GitOps]       → sed 替换 deployment.yaml 中的 image 标签
   [Git Commit & Push]   → git commit + git push
   [Wait ArgoCD Sync]    → ArgoCD 检测到变化并同步到 K8s
   ```

### Step 4: 配置自动触发 (Webhook)

**在 Jenkins 上:**
```
Job → Configure → Build Triggers → ☑ Poll SCM
Schedule: H/5 * * * *   (每 5 分钟轮询一次)
```

**更推荐的方式 — Webhook:**
```powershell
# 在 Git 服务器上配置 webhook:
# URL: http://jenkins.test:31716/github-webhook/
# 或: http://jenkins.test:31716/git/notifyCommit?url=<repo-url>
```

### Step 5: 验证完整链路

```bash
# 1. 确认 ArgoCD Application 状态
kubectl get application -n argocd snownlp-demo
# 期望: HEALTHY, SYNCED

# 2. 确认 K8s Deployment 使用了新镜像
kubectl -n monitoring get deploy snownlp-demo -o jsonpath='{.spec.template.spec.containers[0].image}'
# 期望: 192.168.1.61/monitoring/snownlp-demo:20260625-1300-1

# 3. 手动改代码后触发完整流程
echo '# test change' >> 01-app/app.py
git add . && git commit -m "test: trigger pipeline" && git push
# → Jenkins 自动构建 → ArgoCD 自动同步 → K8s Pod 更新
```

---

## 五、关键文件清单

| 文件 | 位置 | 作用 |
|------|------|------|
| `Jenkinsfile` | snownlp-observability-demo/ | CI 流水线定义 (6 Stage) |
| `argocd/snownlp-demo-app.yaml` | snownlp-observability-demo/argocd/ | ArgoCD 应用定义 |
| `argocd/application.yaml` | 可观测性/argocd/ | 监控基础设施的 ArgoCD 应用 |
| `01-app/deployment.yaml` | snownlp-observability-demo/01-app/ | K8s Deployment (image 标签由 Jenkins 更新) |
| `01-app/service.yaml` | snownlp-observability-demo/01-app/ | K8s Service (静态不变) |

---

## 六、日常操作流程

### 6.1 修改应用代码并发布

```bash
# 1. 修改代码
vim 01-app/app.py

# 2. 提交并推送
git add 01-app/app.py
git commit -m "feat: 新增情感分析维度"
git push origin main

# 3. Jenkins 自动触发 → ArgoCD 自动同步
#    不需要手动操作 K8s 或 Jenkins!
```

### 6.2 回滚到上一版本

```bash
# 方式1: ArgoCD UI 操作
# → Applications → snownlp-demo → History and Rollback → 选旧版本 → Rollback

# 方式2: Git revert + push
git revert HEAD
git push origin main
# → Jenkins 构建旧代码 → ArgoCD 自动同步

# 方式3: ArgoCD CLI
argocd app rollback snownlp-demo 1
```

### 6.3 查看同步状态

```bash
# CLI
argocd app get snownlp-demo --insecure --grpc-web

# API
curl -s http://argocd.test:31716/api/v1/applications/snownlp-demo \
  -H "Authorization: Bearer $(argocd account generate-token)"

# UI
# 打开 http://argocd.test:31716 → Applications → snownlp-demo
```

---

## 七、故障排查

| 症状 | 可能原因 | 解决 |
|------|---------|------|
| Jenkins 无法拉取代码 | 未配置 Git 凭据 | Jenkins → Credentials → 添加 SSH Key 或用户名密码 |
| `docker build` 失败 | agent 无 docker 权限 | `usermod -aG docker jenkins` |
| `docker push` 被拒 | 未登录 Harbor | 在 agent 上 `docker login 192.168.1.61` |
| ArgoCD 不自动同步 | 轮询周期太长 / 配置错误 | 检查 `syncPolicy.automated`；ArgoCD → Settings → 调短 reconciliation timeout |
| ArgoCD OutOfSync | deployment.yaml 未 commit | 确认 Stage 5 执行了 `git push` |
| Git push 失败 | 未配置 Git user.email | Jenkinsfile 中已配置 `jenkins@cicd.local` |
| Pod CrashLoopBackOff | SkyWalking OAP 不可达 | 确认 `skywalking-oap.monitoring:11800` 可达 |

---

## 八、方案对比速查

| | 方案一 Jenkins+ArgoCD | 方案二 GitLab+ArgoCD | 方案三 纯GitOps |
|------|------|------|------|
| **CI 工具** | Jenkins | GitLab CI Runner | 无 (手动构建) |
| **CD 工具** | ArgoCD | ArgoCD | ArgoCD |
| **镜像构建** | Jenkins Pipeline 自动 | `.gitlab-ci.yml` 自动 | 开发者手动 `docker build` |
| **触发方式** | Webhook+轮询 | Git push → GitLab Runner | 手动更新 Git 清单 |
| **适用场景** | 传统企业 (已有 Jenkins) | 自建 GitLab 私有部署 | 运维/平台团队 |
| **学习成本** | 中等 | 低 (与 GitLab 一体) | 高 (无 CI) |
| **灵活性** | 最高 (Groovy 脚本) | 高 (YAML 配置) | 低 |
