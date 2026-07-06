# P2: Argo Rollouts 灰度发布

> **状态**: ✅ 完成 | **日期**: 2026-06-26 | **前置**: P0 Kustomize 重构

---

## 目标

将 tomcat 三个环境的 **Deployment** 迁移到 **Argo Rollouts**，实现：

| 环境 | 发布策略 | Promotion | 说明 |
|------|----------|-----------|------|
| **dev** | 金丝雀 (Canary) | 自动 | 20% → 40% → 100%，每步停留 60s |
| **staging** | 蓝绿 (BlueGreen) | 手动 | 新版本先部署预览 → 手工推进 → 旧版 120s 后下线 |
| **prod** | 蓝绿 (BlueGreen) | 手动 | 新版本先预览验证 → 手工推进 → 旧版保留 600s |

---

## 资源消耗

| 组件 | 内存 | 说明 |
|------|------|------|
| Argo Rollouts Controller | ~50Mi | 单个 Pod，无额外数据库 |
| 各环境预览 Pod (staging/prod) | 各 1 副本 | 蓝绿发布时的 preview stack |

---

## 文件结构

```
方案3-Argo-Rollouts/
├── README.md                          ← 本文档
├── 01-install-rollouts.sh             ← 安装 Argo Rollouts (Linux/macOS)
├── 01-install-rollouts.ps1            ← 安装 Argo Rollouts (Windows)
├── 02-apply-rollouts.sh               ← 部署 Rollout 清单 (Linux/macOS)
├── 02-apply-rollouts.ps1              ← 部署 Rollout 清单 (Windows)
├── k8s/
│   ├── base/
│   │   ├── rollout.yaml               ← Base Rollout 模板
│   │   ├── service.yaml               ← Service (不变)
│   │   └── kustomization.yaml
│   └── overlays/
│       ├── dev/                       ← 金丝雀: 1 副本, 20%→40%→100%
│       │   ├── kustomization.yaml
│       │   ├── namespace.yaml
│       │   └── secret.yaml
│       ├── staging/                   ← 蓝绿: 2 副本, preview 1 副本
│       │   ├── kustomization.yaml
│       │   ├── preview-service.yaml   ← 蓝绿预览 Service
│       │   ├── namespace.yaml
│       │   └── secret.yaml
│       └── prod/                      ← 蓝绿: 2 副本, 高资源, 手动推进
│           ├── kustomization.yaml
│           ├── preview-service.yaml
│           ├── namespace.yaml
│           └── secret.yaml
└── argocd/
    ├── tomcat-app-dev.yaml            ← DEV ArgoCD Application (GitOps)
    ├── tomcat-app-staging.yaml        ← STAGING ArgoCD Application
    └── tomcat-app-prod.yaml           ← PROD ArgoCD Application
```

---

## 部署步骤

### Step 1: 安装 Argo Rollouts

```bash
# Linux/macOS
bash 01-install-rollouts.sh

# Windows PowerShell
powershell -File 01-install-rollouts.ps1
```

### Step 2: 部署 Rollout 清单

```bash
# 先禁用 ArgoCD 自动同步 (防止回滚)
kubectl patch app tomcat-app-dev -n argocd --type=merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'
kubectl patch app tomcat-app-staging -n argocd --type=merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'
kubectl patch app tomcat-app-prod -n argocd --type=merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'

# 应用 Rollout
bash 02-apply-rollouts.sh
```

### Step 3: 验证

```bash
# 查看所有 Rollout
kubectl argo rollouts list rollout -A

# 查看 DEV 金丝雀发布状态
kubectl argo rollouts get rollout tomcat-app -n tomcat-dev --watch

# 查看 STAGING 蓝绿发布
kubectl argo rollouts get rollout tomcat-app -n tomcat-staging

# 手动推进 STAGING 蓝绿
kubectl argo rollouts promote tomcat-app -n tomcat-staging

# 查看 PROD 蓝绿发布
kubectl argo rollouts get rollout tomcat-app -n tomcat-prod

# 手动推进 PROD 蓝绿
kubectl argo rollouts promote tomcat-app -n tomcat-prod
```

---

## 使用场景

### 场景 1: 日常发布 (金丝雀 - DEV)

```bash
# 代码提交 → CI 构建镜像 push → ArgoCD Image Updater 自动更新 Rollout 镜像
# Argo Rollouts 自动按 20% → 40% → 100% 分批切换流量
kubectl argo rollouts get rollout tomcat-app -n tomcat-dev --watch
```

### 场景 2: 预发布验证 (蓝绿 - STAGING)

```bash
# 新镜像被 ArgoCD Image Updater 推入后，Rollout 自动创建 preview stack
# 验证 preview 版本:
kubectl port-forward -n tomcat-staging svc/tomcat-app-preview 8080:8080

# 验证通过后手动推进:
kubectl argo rollouts promote tomcat-app -n tomcat-staging

# 验证失败可中止 (保留旧版):
kubectl argo rollouts abort tomcat-app -n tomcat-staging
```

### 场景 3: 生产发布 (蓝绿 - PROD)

```bash
# 预览新版本:
kubectl port-forward -n tomcat-prod svc/tomcat-app-preview 8080:8080

# 生产验证通过后手动推进:
kubectl argo rollouts promote tomcat-app -n tomcat-prod

# 紧急回滚 (切回旧版本):
kubectl argo rollouts undo tomcat-app -n tomcat-prod
```

---

## Rollout 策略对比

| 特性 | Canary (DEV) | BlueGreen (STAGING) | BlueGreen (PROD) |
|------|-------------|---------------------|------------------|
| 副本数 | 1 | 2 (active) + 1 (preview) | 2 (active) + 1 (preview) |
| 流量切换 | 逐步 (20/40/100) | 一次性切换 | 一次性切换 |
| 实现方式 | 标签权重 | Service Selector 切换 | Service Selector 切换 |
| 验证窗口 | 每步 60s | 手动确认 | 手动确认 |
| 旧版保留 | 否 | 120s 后下线 | 600s 后下线 |
| 回滚 | `undo` 重建旧版 | `abort` 切回旧 Pod | `abort` 切回旧 Pod |
| 额外开销 | 无 | +1 preview Pod | +1 preview Pod |

---

## 从当前 Deployment 迁移对比

```
                  迁移前 (P1)              迁移后 (P2)
                 ┌──────────┐           ┌──────────────┐
  DEV   复制     │ 滚更 1副本│ ──────→   │ 金丝雀 1副本  │
                 └──────────┘           └──────────────┘

                 ┌──────────┐           ┌──────────────┐
  STAGING复制    │ 滚更 2副本│ ──────→   │ 蓝绿 2+1副本  │
                 └──────────┘           └──────────────┘

                 ┌──────────┐           ┌──────────────┐
  PROD  复制     │ 滚更 2副本│ ──────→   │ 蓝绿 2+1副本  │
                 └──────────┘           └──────────────┘
```

---

## GitLab 恢复后操作

当前 GitLab 已关停，Rollout 通过 `kubectl apply` 直接部署。GitLab 恢复后：

1. **将 k8s/ 目录提交到 Git 仓库**
   ```bash
   git add argo-rollouts/k8s/
   git commit -m "P2: Argo Rollouts for tomcat-app"
   git push origin main
   ```

2. **更新 ArgoCD Application 源路径**
   ```bash
   # 修改 Application 的 source.path 指向新 kustomize 路径
   kubectl patch app tomcat-app-dev -n argocd --type=merge \
     -p '{"spec":{"source":{"path":"argo-rollouts/k8s/overlays/dev"}}}'
   ```

3. **恢复 ArgoCD auto-sync**
   ```bash
   kubectl patch app tomcat-app-dev -n argocd --type=merge \
     -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
   ```

---

## 常见问题

**Q: 为什么 DEV 用金丝雀而不是蓝绿?**
A: 金丝雀比蓝绿更省资源（无需额外 preview Pod），DEV 环境 1 副本时蓝绿开销不划算。金丝雀按比例分配流量到旧新版 Pod，更适合开发环境快速迭代。

**Q: `kubectl argo rollouts promote` 后多久生效?**
A: 立即生效。`scaleDownDelaySeconds` 只控制旧版 Pod 何时删除，不影响流量切换速度。

**Q: 如何查看 Rollouts Dashboard?**
```bash
kubectl argo rollouts dashboard -n tomcat-dev
# 浏览器访问 http://localhost:3100
```

**Q: PROD 的 scaleDownDelaySeconds=600s 意味着什么?**
A: 新版本上线后，旧版 Pod 保留 10 分钟再删除。如果 10 分钟内发现新版本有问题，可以 `abort` 切回旧版，无需重新拉镜像启动。
