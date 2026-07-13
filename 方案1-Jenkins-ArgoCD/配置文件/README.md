# 配置文件目录

> 本目录存放 Jenkins（CI 持续集成工具） + ArgoCD GitOps 全链路涉及的所有 YAML、XML 配置和脚本文件。
> 每个文件都带有详细的中文注释，可以直接复制使用。

## 📁 目录结构

```
配置文件/
├── README.md                           ← 本说明文件
│
├── git-server/                         ← Git Server 配置
│   └── git-server-deployment.yaml      ← PVC + InitJob + Deployment(双容器) + Service
│
├── jenkins/                            ← Jenkins 配置
│   ├── jenkins-deploy.yaml             ← PVC + SA + RBAC + Deployment + Service + Ingress
│   └── jenkins-job-config.xml          ← Pipeline Job 定义（Inline Script 方式）
│
├── argocd/                             ← ArgoCD 配置
│   └── repo-secret.yaml                ← Git 仓库注册 Secret
│
└── scripts/                            ← 运维脚本
    └── one-click-init.sh               ← 一键初始化参考脚本
```

## 📋 文件说明

### 1. git-server-deployment.yaml

| 项目 | 说明 |
|------|------|
| **用途** | 在 K8s（Kubernetes，容器编排引擎） 集群中部署内网 Git 服务器 |
| **组件** | PVC（持久化）+ InitJob（初始化仓库）+ Deployment（双容器）+ Service（服务，集群内服务发现） |
| **容器** | Nginx (:80, 浏览器查看) + Git Daemon (:9418, git:// 协议) |
| **关键点** | `--enable=receive-pack` 允许 push；`--base-path=/repos` 简化 clone 路径 |
| **命名空间** | `git` |
| **部署** | `kubectl apply -f git-server-deployment.yaml` |

### 2. jenkins-deploy.yaml

| 项目 | 说明 |
|------|------|
| **用途** | 在 K8s 集群中部署 Jenkins CI 服务器 |
| **组件** | PVC + ServiceAccount + ClusterRole/Binding + Deployment（部署，无状态工作负载） + Service + Ingress |
| **关键点** | 挂载宿主机 docker.sock → 容器内直接执行 docker build/push |
| **权限** | ClusterRole 高权限（可管理 K8s 资源），生产环境建议缩小范围 |
| **命名空间** | `jenkins` |
| **部署** | `kubectl apply -f jenkins-deploy.yaml` |

### 3. jenkins-job-config.xml

| 项目 | 说明 |
|------|------|
| **用途** | Jenkins Pipeline（流水线） Job 的 XML 配置文件 |
| **方式** | Inline Script（CpsFlowDefinition），非 SCM-based Pipeline |
| **流水线** | 6 个 Stage：Checkout → Build → Push → Update GitOps（以 Git 为唯一真相源的运维模式） → Git Push → Wait Sync |
| **关键点** | 用 sed 替换基础镜像地址解决内网问题；git push 后 ArgoCD（GitOps 持续交付工具） 自动同步 |
| **部署** | 通过 REST API 创建 `curl -X POST /createItem?name=... --data-binary @jenkins-job-config.xml` |

### 4. repo-secret.yaml

| 项目 | 说明 |
|------|------|
| **用途** | 将 Git 仓库注册到 ArgoCD |
| **仓库** | snownlp-observability-demo（业务应用）+ 可观测性（监控配置） |
| **协议** | `git://`（Git Daemon 9418 端口），无需密码 |
| **命名空间** | `argocd` |
| **部署** | `kubectl apply -f repo-secret.yaml` |

### 5. one-click-init.sh

| 项目 | 说明 |
|------|------|
| **用途** | 一键部署全链路的参考脚本 |
| **注意** | 仅作流程参考，实际建议分阶段手动执行 |
| **执行** | `chmod +x one-click-init.sh && ./one-click-init.sh` |

## 🔗 其他重要文件（不在本目录）

以下文件位于各自的子项目中：

| 文件 | 位置 | 说明 |
|------|------|------|
| `snownlp-demo-app.yaml` | `../../snownlp-observability-demo/argocd/` | ArgoCD Application（业务应用） |
| `application.yaml` | `../../可观测性/argocd/` | ArgoCD Application（监控栈） |
| `Jenkinsfile` | `../../snownlp-observability-demo/` | 原始 Jenkinsfile（参考用，未使用） |
| `save-monitoring.sh` | `../../可观测性/` | 监控栈一键备份 |
| `restore-monitoring.sh` | `../../可观测性/` | 监控栈一键恢复 |
| `delete-monitoring.sh` | `../../可观测性/` | 监控栈一键缩容 |

## ⚙️ 环境变量替换

所有文件中的以下值需要替换为你的实际环境：

| 搜索替换 | 默认值 | 说明 |
|---------|--------|------|
| `192.168.1.61` | Harbor（私有镜像仓库） 镜像仓库地址 | 你的 Harbor IP/域名 |
| `192.168.1.61/library` | 基础镜像前缀 | 你的镜像库路径 |
| `local-path` | StorageClass 名称 | 你的集群 StorageClass |
| `nginx` | Ingress（入口规则） Controller 类名 | 你的 Ingress Controller |
| `jenkins.test` | Jenkins 域名 | 你的 Jenkins 域名或 IP |
| `argocd.test` | ArgoCD 域名 | 你的 ArgoCD 域名或 IP |
| `:31716` | Ingress NodePort | 你的 Ingress Controller 端口 |
| `<HARBOR_USER>` | Harbor 用户名 | 你的 Harbor 凭证 |
| `<HARBOR_PASS>` | Harbor 密码 | 你的 Harbor 凭证 |

> **推荐**: 修改 `项目实战/部署工具/env.sh` 统一管理所有配置，无需逐个文件替换。
>
> ```bash
> cd 项目实战/
> cp env.sh env.local.sh       # 创建本地配置
> vim env.local.sh              # 填入实际值
> source env.local.sh           # 让脚本自动加载
> ```
