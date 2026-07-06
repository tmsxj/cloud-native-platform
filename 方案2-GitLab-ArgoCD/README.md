# GitLab + ArgoCD GitOps CI/CD 总结

> 基于自建 K8s 集群（Harbor + ArgoCD + GitLab + GitLab Runner）的真实环境验证
> 验证项目：`tomcat-app`（Java Web 应用，Tomcat 部署）
> 对比方案 1（Jenkins + Git Server），本方案用 GitLab CI 替代 Jenkins

---

## 方案对比

| 维度 | 方案 1: Jenkins + Git Server | 方案 2: GitLab + GitLab CI |
|------|---------------------------|--------------------------|
| **代码仓库** | Git Daemon (git://) | GitLab (HTTP/SSH) |
| **CI 引擎** | Jenkins (独立部署) | GitLab CI (内置于 GitLab) |
| **CD 引擎** | ArgoCD | ArgoCD (复用) |
| **镜像仓库** | Harbor | Harbor (复用) |
| **流水线定义** | Jenkinsfile (Groovy) | .gitlab-ci.yml (YAML) |
| **应用语言** | Python (FastAPI + SnowNLP) | Java (Servlet + JSP) |
| **运行容器** | Python 自定义镜像 | Tomcat 9 |
| **命名空间** | monitoring | tomcat-demo |

---

## 一、架构总览

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     GitOps CI/CD 全链路 (GitLab + ArgoCD)                   │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌──────────┐    git push     ┌──────────────┐                           │
│  │ 开发者     │──────────────▶ │   GitLab      │                           │
│  │ 修改代码   │                │ (gitlab NS)  │                           │
│  └──────────┘                └──────┬───────┘                           │
│                                     │                                     │
│                         自动触发     │                                     │
│                                     ▼                                     │
│  ┌──────────────────────────────────────────────────────────────────┐    │
│  │                    GitLab CI Pipeline (9 Stage)                    │    │
│  │                    Runner: Docker Executor + docker.sock          │    │
│  │                                                                    │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐          │    │
│  │  │ Stage 1  │  │ Stage 2  │  │ Stage 2  │  │ Stage 3  │          │    │
│  │  │ unit-test│─▶│checkstyle│─▶│ spotbugs │─▶│  build   │          │    │
│  │  │ 单测     │  │ 代码风格  │  │ 缺陷扫描  │  │ Maven编译 │          │    │
│  │  └──────────┘  └──────────┘  └──────────┘  └────┬─────┘          │    │
│  │                                                  │                 │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐       │                 │    │
│  │  │ Stage 5  │◀─│ Stage 4  │◀─┘           │       │                 │    │
│  │  │ docker   │  │ docker   │                               │       │    │
│  │  │ push     │  │ build    │                               │       │    │
│  │  └────┬─────┘  └──────────┘                               │       │    │
│  │       │                                                     │       │    │
│  │       ▼                                                     │       │    │
│  │  ┌──────────┐  ┌──────────────┐  ┌──────────────┐         │       │    │
│  │  │ Stage 6  │─▶│  Stage 7     │─▶│  Stage 8     │         │       │    │
│  │  │deploy-dev│  │deploy-staging│  │ deploy-prod  │         │       │    │
│  │  │DEV部署   │  │STAGING部署   │  │ PROD部署(手动)│         │       │    │
│  │  └──────────┘  └──────────────┘  └──────────────┘         │       │    │
│  └───────────────────────┬────────────────────────────────────┘       │    │
│                          │ git push (更新了 k8s/{dev,staging,prod}/)  │    │
│                          ▼                                             │    │
│  ┌──────────────────────────────────────────────────────────────────┐    │
│  │                      ArgoCD GitOps Engine                          │    │
│  │                      (复用方案1的 ArgoCD 实例)                      │    │
│  │                                                                    │    │
│  │  ┌────────────────────────────────────────────────────────────┐  │    │
│  │  │  Application: tomcat-app-dev / staging / prod               │  │    │
│  │  │  Repo: http://gitlab.gitlab.svc/root/tomcat-app.git         │  │    │
│  │  │  Path: k8s/dev/  k8s/staging/  k8s/prod/                    │  │    │
│  │  │  Target: tomcat-dev/staging/prod namespace                  │  │    │
│  │  │  Sync: automated (selfHeal + prune)                         │  │    │
│  │  └────────────────────────────────────────────────────────────┘  │    │
│  │                          │                                        │    │
│  │   每 3min 检测 Git 变化  │  检测到各环境 deployment.yaml 变更       │    │
│  │                          ▼                                        │    │
│  │  ┌────────────────────────────────────────────────────────────┐  │    │
│  │  │  kubectl apply -f k8s/dev/deployment.yaml                   │  │    │
│  │  │  kubectl apply -f k8s/staging/deployment.yaml               │  │    │
│  │  │  kubectl apply -f k8s/prod/deployment.yaml                  │  │    │
│  │  └────────────────────────────────────────────────────────────┘  │    │
│  └───────────────────────┬──────────────────────────────────────────┘    │
│                          │                                                  │
│                          ▼                                                  │
│  ┌──────────────────────────────────────────────────────────────────┐    │
│  │      Kubernetes Cluster (tomcat-demo/dev/staging/prod)                 │    │
│  │                                                                   │    │
│  │  ┌─────────────────────┐  ┌─────────────────┐                    │    │
│  │  │ tomcat-app           │  │ tomcat-app      │                    │    │
│  │  │ Deployment (2 副本)   │  │ Service         │                    │    │
│  │  │ image: ...:vN-abc123 │  │ port: 8080      │                    │    │
│  │  └─────────┬───────────┘  └────────┬────────┘                    │    │
│  │            │                       │                              │    │
│  │            ▼                       ▼                              │    │
│  │  ┌─────────────────────────────────────────────────────────┐    │    │
│  │  │  Tomcat 9 + Java 11                                      │    │    │
│  │  │  /         → index.jsp  (Pod 信息展示)                   │    │    │
│  │  │  /health   → JSON (健康检查)                              │    │    │
│  │  └─────────────────────────────────────────────────────────┘    │    │
│  └──────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 二、项目体系

### 2.1 tomcat-app（业务应用 + CI/CD）

```
tomcat-app/                          ← GitLab 仓库
├── .gitlab-ci.yml                   ← CI 流水线定义（9 Stage）
├── pom.xml                          ← Maven 构建配置
├── Dockerfile                       ← 多阶段镜像构建
├── k8s/                             ← ⚡ 被 ArgoCD 监听的清单目录
│   ├── dev/deployment.yaml          ← DEV 环境部署清单
│   ├── staging/deployment.yaml      ← STAGING 环境部署清单
│   └── prod/deployment.yaml         ← PROD 环境部署清单
└── src/                             ← Java Web 源码
    └── main/
        ├── java/com/demo/
        │   └── HealthServlet.java   ← /health 健康检查
        └── webapp/
            └── index.jsp             ← 主页面
```

### 2.2 共用基础设施（方案1已部署）

| 组件 | 命名空间 | 说明 |
|------|---------|------|
| **Harbor** | harbor | 镜像仓库（复用方案1） |
| **ArgoCD** | argocd | GitOps 引擎（复用方案1） |
| **GitLab** | gitlab | 本方案新增 |
| **GitLab Runner** | gitlab | 本方案新增 |

---

## 三、GitOps 核心工作原理

### 与方案1的关键区别

```
方案1 (Jenkins):
  开发者 push → Jenkins clone 另一个仓库 → 构建 → sed → push 另一个仓库
  缺点: 需要两个 Git 仓库协作，Jenkins 独立部署

方案2 (GitLab CI):
  开发者 push → GitLab 自动触发 CI → 测试+扫描+构建 → sed → push 同一个仓库
  优点: 单一仓库，GitLab 内置 CI，无需额外组件，内置质量门禁
```

### 完整数据流

```
Step 1: 开发者 git push 代码到 GitLab main 分支
    ↓
Step 2: GitLab 自动触发 CI Pipeline (检测 .gitlab-ci.yml)
    ↓
Step 3: Stage 1 → unit-test Maven 单元测试 + 覆盖率报告
    ↓
Step 4: Stage 2 → checkstyle + spotbugs 代码质量门禁 (并行)
    ↓
Step 5: Stage 3 → Maven 编译 WAR 包 (跳过测试，防止重复)
    ↓
Step 6: Stage 4 → Docker Build 构建镜像
        镜像标签格式: v{PIPELINE_ID}-{COMMIT_SHORT_SHA}
    ↓
Step 7: Stage 5 → docker push 推送至 Harbor
    ↓
Step 8: Stage 6 → sed 替换 k8s/dev/deployment.yaml → git push → ArgoCD 同步 DEV
    ↓
Step 9: Stage 7 → sed 替换 k8s/staging/deployment.yaml → git push → ArgoCD 同步 STAGING
    ↓
Step 10: Stage 8 → sed 替换 k8s/prod/deployment.yaml → git push → ArgoCD 同步 PROD (手动触发)
    ↓
Step 11: ArgoCD 检测到各环境 k8s/ 目录变化 (默认 3min 轮询)
    ↓
Step 12: ArgoCD 自动执行 kubectl apply，将新镜像部署到对应环境
```

---

## 四、环境信息

### K8S 命名空间

| 命名空间 | 用途 | 组件 |
|---------|------|------|
| `gitlab` | GitLab 服务 | GitLab CE + GitLab Runner |
| `tomcat-demo` | 演示应用 (旧版) | Tomcat App Deployment + Service |
| `tomcat-dev` | DEV 环境 | Tomcat App (ArgoCD 托管) |
| `tomcat-staging` | STAGING 环境 | Tomcat App (ArgoCD 托管) |
| `tomcat-prod` | PROD 环境 | Tomcat App (ArgoCD 托管) |
| `argocd` | GitOps 引擎 | ArgoCD (复用方案1) |

### 组件地址

| 组件 | 地址 | 凭证 |
|------|------|------|
| **GitLab** | `http://gitlab.test:31080` | root / (初始密码) |
| **ArgoCD** | `http://argocd.test:31716` | admin / (复用) |
| **Harbor** | `192.168.1.61` | admin / Harbor12345 |
| **Tomcat App** | `http://tomcat-app.tomcat-demo.svc:8080` | 无需认证 |

---

## 五、两个 ArgoCD Application（同一实例）

| 属性 | snownlp-demo (方案1) | tomcat-app (方案2) |
|------|---------------------|-------------------|
| **Git 仓库** | snownlp-observability-demo | tomcat-app |
| **仓库协议** | git:// | http:// |
| **监听路径** | `01-app/` | `k8s/` |
| **目标命名空间** | `monitoring` | `tomcat-demo` |
| **自动同步** | prune=true, selfHeal=true | prune=true, selfHeal=true |
| **触发方式** | Jenkins 更新 deployment.yaml | GitLab CI 更新 deployment.yaml |

---

## 六、GitLab CI 9 Stage 详解

### Stage 1: unit-test (单元测试)
- 使用 Harbor 中的 `maven:3.9-eclipse-temurin-17-alpine` 镜像
- 执行 `mvn test -B`
- 产出 JUnit 报告 + 覆盖率数据作为 artifact
- **质量门禁第一步：代码逻辑正确性**

### Stage 2: static-scan (代码扫描，并行执行)
- **checkstyle**：代码风格检查，产出 `checkstyle-result.xml`
- **spotbugs**：静态缺陷扫描，产出 `spotbugsXml.xml`（allow_failure=true）
- **质量门禁第二步：代码规范与潜在缺陷**

### Stage 3: build (Maven 编译)
- 执行 `mvn clean package -DskipTests -B`（跳过测试，防止重复）
- 产出 WAR 包作为 artifact，有效期 1 小时

### Stage 4: docker-build (镜像构建)
- 使用 Harbor 中的 `docker:24-dind` 镜像
- 多阶段 Dockerfile: Maven → Tomcat
- 构建产物保存为 `/tmp/image.tar` artifact
- 标签格式: `v{PIPELINE_ID}-{SHORT_SHA}` + `latest`

### Stage 5: docker-push (推送到 Harbor)
- 从 artifact 加载镜像 → 推送到 Harbor
- 推送版本标签 + latest 标签
- Harbor 项目: `tomcat-demo`

### Stage 6: deploy-dev (部署到开发环境)
- 使用 YAML Anchor `.deploy_template` 复用逻辑
- `git checkout -B main` → `git fetch + rebase` → `sed` 替换 image → `git push`
- 更新 `k8s/dev/deployment.yaml`
- 提交信息加 `[skip ci]` 防止循环触发
- ArgoCD 自动检测并同步到 `tomcat-dev` 命名空间

### Stage 7: deploy-staging (部署到预发布环境)
- 复用 deploy 模板，依赖 deploy-dev 完成
- 更新 `k8s/staging/deployment.yaml`
- ArgoCD 自动同步到 `tomcat-staging` 命名空间

### Stage 8: deploy-prod (部署到生产环境)
- **手动触发**（`when: manual`），仅 main 分支
- 更新 `k8s/prod/deployment.yaml`
- ArgoCD 自动同步到 `tomcat-prod` 命名空间
- **安全实践：生产部署需人工确认**

### 关键技术修复（Pipeline #58 验证）

| 问题 | 修复方案 |
|------|---------|
| detached HEAD 导致 `git push` 失败 | `git checkout -B main` 强制绑定分支 |
| `git rebase` 与文件修改顺序冲突 | 先 `git fetch + rebase`，再 `sed` 修改文件 |
| K8s 集群内无法用 `localhost` 访问 GitLab | 改用 `gitlab.gitlab.svc.cluster.local` |

---

## 七、目录结构

```
方案2-GitLab-ArgoCD/
├── README.md                     ← 架构总览、GitOps 流程图、环境信息
├── 关键配置详解.md                 ← 每份配置的设计意图、变量含义
├── 故障排查手册.md                 ← 实战踩坑场景 + 快速诊断命令
├── 项目结构对照.md                 ← 与方案1的架构关系对照
├── 端到端操作实录.md               ★ 从零搭建全过程的命令实录
└── 配置文件/
    ├── gitlab/                    ← GitLab + Runner 部署配置
    ├── argocd/                    ← ArgoCD Application 定义
    ├── tomcat-app/                ← Java Web 应用源码 + CI 配置
    ├── scripts/                   ← 一键初始化脚本
    └── README.md                  ← 配置目录使用指南
```

---

## 八、文档关系说明

| 文档 | 适合场景 |
|------|---------|
| **端到端操作实录** | 新人上手、环境重建、理解"到底敲了什么命令" |
| **配置文件/** | 直接复制 YAML/Java/Shell，避免文档格式混乱 |
| **关键配置详解** | 理解每份配置为什么这样写 |
| **故障排查手册** | 出问题时快速定位和修复 |
| **项目结构对照** | 对比方案1理解两套架构的关系 |
| **README（本文）** | 快速了解整体架构和核心原理 |
