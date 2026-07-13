# 配置文件目录 - GitLab + ArgoCD（GitOps 持续交付工具） 方案

> 所有独立 YAML/XML/Shell/Java 配置，带中文注释，可直接复制使用。

## 目录结构

```
配置文件/
├── README.md                    ← 本文档
├── gitlab/
│   ├── gitlab-deploy.yaml       ← GitLab CE 全栈部署 (PVC + Service + Deployment)
│   └── gitlab-runner-deploy.yaml ← GitLab Runner 部署 (SA + RBAC + Secret + Deployment)
├── argocd/
│   └── tomcat-app.yaml          ← ArgoCD Application 定义 (自动同步配置)
├── tomcat-app/
│   ├── .gitlab-ci.yml           ← GitLab CI 流水线 (5 阶段)
│   ├── pom.xml                  ← Maven 构建配置
│   ├── Dockerfile               ← 多阶段镜像构建 (Maven → Tomcat)
│   ├── deployment.yaml          ← K8S Deployment + Service + Secret
│   └── src/                     ← Java Web 应用源码
│       └── main/
│           ├── java/com/demo/
│           │   └── HealthServlet.java  ← /health 健康检查接口
│           └── webapp/
│               └── index.jsp          ← 主页面 (展示部署信息)
└── scripts/
    └── one-click-init.sh        ← 一键初始化脚本 (参考)
```

## 使用方法

### 1. 变量替换

部署前，全文替换以下变量：

| 搜索 | 替换为 | 说明 |
|------|--------|------|
| `192.168.1.61` | 你的 Harbor（私有镜像仓库） IP | 镜像仓库地址 |
| `local-path` | 你的 StorageClass | K8S 存储类 |
| `gitlab.test:31080` | 你的 GitLab（代码托管 + CI 平台） 域名 | GitLab 访问地址 |
| `YOUR_REGISTRATION_TOKEN` | GitLab Runner（GitLab CI 执行器） Token | 从 GitLab 管理界面获取 |
| `<HARBOR_PASS>` | 你的 Harbor 密码 | 环境变量自动加载 |

> **推荐**: 修改 `项目实战/部署工具/env.sh` 统一管理所有配置，不再需要逐个文件替换。
>
> ```bash
> cd 项目实战/
> cp env.sh env.local.sh       # 创建本地配置
> vim env.local.sh              # 填入实际值
> source env.local.sh           # 让脚本自动加载
> ```

### 2. 部署顺序

```
1. GitLab           → kubectl apply -f gitlab/gitlab-deploy.yaml
2. Harbor 镜像准备   → docker pull/push 基础镜像
3. GitLab Runner    → 替换 Registration Token → kubectl apply
4. tomcat-demo NS   → kubectl create namespace + harbor-regcred
5. 推送代码到 GitLab → git remote add + git push
6. ArgoCD 注册仓库   → argocd repo add
7. ArgoCD Application → kubectl apply -f argocd/tomcat-app.yaml
```

### 3. GitLab CI Variables 配置

在 GitLab 项目 `Settings → CI/CD（持续集成/持续交付） → Variables` 中添加：

| Key | Value | 说明 |
|-----|-------|------|
| `HARBOR_USER` | admin | Harbor 用户名 |
| `HARBOR_PASS` | `<你的Harbor密码>` | Harbor 密码（通过 CI Variables 注入） |
| `GITLAB_TOKEN` | (Personal Access Token) | GitLab API Token (write_repository) |
