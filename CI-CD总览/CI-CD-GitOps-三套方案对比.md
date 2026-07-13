# CI/CD（持续集成/持续交付） 三套方案对比实现

> 基于当前自建 K8s 集群（Harbor + ArgoCD + Jenkins（CI 持续集成工具））的真实环境
> 假设项目：HiAgent 智能体平台（多组件、多环境）

---

## 架构总览

```
┌──────────────────────────────────────────────────────────────────┐
│                    三套方案对比架构                                │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  方案1: Jenkins + ArgoCD                                          │
│  ┌──────────┐  push镜像  ┌──────────┐  更新Git  ┌──────────┐    │
│  │ Jenkins  │───────────>│  Harbor  │────────>  │  ArgoCD  │    │
│  │  (CI)    │            │ 192.1.61 │ image tag │  (CD)    │    │
│  │ build/test│           └──────────┘           │ auto-sync│    │
│  └──────────┘                                   └──────────┘    │
│                                                                   │
│  方案2: GitLab CI + ArgoCD                                       │
│  ┌──────────┐  push镜像  ┌──────────┐  更新Git  ┌──────────┐    │
│  │ GitLab   │───────────>│  Harbor  │────────>  │  ArgoCD  │    │
│  │ Runner   │            │ 192.1.61 │ image tag │  (CD)    │    │
│  │  (CI)    │            └──────────┘           │ auto-sync│    │
│  └──────────┘                                   └──────────┘    │
│                                                                   │
│  方案3: 纯 GitOps (ArgoCD Only)                                  │
│  ┌──────────┐  docker build      ┌──────────┐  watch Git┌──────┐│
│  │ 开发者    │──────────────────>│  Harbor  │<──────────│ArgoCD││
│  │ 手动构建  │                   │ 192.1.61 │           │(CD)  ││
│  └──────────┘                   └──────────┘           └──────┘│
│                                   ↑ 更新 Git 中 image tag       │
└──────────────────────────────────────────────────────────────────┘
```

---

## 核心联动机制（三套方案共用）

```
CI 做完后 → 更新 Git 仓库中 K8s 清单的镜像 tag
              ↓
        ArgoCD 自动检测到 Git 变更
              ↓
        ArgoCD 自动同步到集群
```

**关键操作**：CI 阶段最后一步——修改 `kustomization.yaml` 的 `images.newTag`

```yaml
# manifests/overlays/prod/kustomization.yaml
images:
  - name: hiagent-api
    newTag: "abc1234"     # ← CI 自动更新这个值
  - name: hiagent-web
    newTag: "abc1234"
```

---

## 方案1: Jenkins + ArgoCD（GitOps 持续交付工具） 联动

### 架构

```
Git Push → Jenkins Pipeline → Harbor(存镜像) → Git(更新tag) → ArgoCD(自动同步)
```

### 前提条件

- Jenkins 已部署 ✅ (`http://jenkins.test:31716`)
- ArgoCD 已部署 ✅ (`http://argocd.test:31716`)
- Harbor（私有镜像仓库） 已部署 ✅ (`192.168.1.61`)
- Git 仓库：存放 K8s（Kubernetes，容器编排引擎） manifests

### Step 1: 创建 ArgoCD Application

```yaml
# argocd/hiagent-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: hiagent
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: http://192.168.1.61:3000/root/hiagent-manifests.git  # 内网Git
    targetRevision: main
    path: manifests/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: hiagent
  syncPolicy:
    automated:                          # ← 关键：自动同步
      prune: true                       # 删除 Git 中移除的资源
      selfHeal: true                    # 自动修复手动变更
    syncOptions:
      - CreateNamespace=true
```

```bash
kubectl apply -f argocd/hiagent-app.yaml -n argocd
```

### Step 2: Jenkins Pipeline（核心：CI 构建完 → 更新 Git）

```groovy
// Jenkinsfile
pipeline {
    agent any
    
    environment {
        HARBOR = '192.168.1.61'
        GIT_REPO = 'http://192.168.1.61:3000/root/hiagent-manifests.git'
        GIT_CREDENTIALS = 'gitea-credentials'
        DOCKER_CREDENTIALS = 'harbor-credentials'
    }
    
    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['staging', 'production'], description: '部署环境')
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
                    env.IMAGE_TAG = "${GIT_COMMIT_SHORT}-${BUILD_NUMBER}"
                }
            }
        }
        
        stage('Build Images') {
            parallel {
                stage('Build API') {
                    steps {
                        sh """
                            docker build -t ${HARBOR}/library/hiagent-api:${IMAGE_TAG} -f api/Dockerfile .
                            docker push ${HARBOR}/library/hiagent-api:${IMAGE_TAG}
                        """
                    }
                }
                stage('Build Web') {
                    steps {
                        sh """
                            docker build -t ${HARBOR}/library/hiagent-web:${IMAGE_TAG} -f web/Dockerfile .
                            docker push ${HARBOR}/library/hiagent-web:${IMAGE_TAG}
                        """
                    }
                }
            }
        }
        
        stage('Update Git Manifests') {   // ← 核心联动步骤
            steps {
                script {
                    // 克隆 manifests 仓库
                    sh "git clone ${GIT_REPO} manifests-repo"
                    dir('manifests-repo') {
                        sh "git config user.email 'jenkins@hiagent.local'"
                        sh "git config user.name 'Jenkins CI'"
                        
                        // 用 kustomize edit 更新镜像 tag
                        sh """
                            cd manifests/overlays/staging
                            kustomize edit set image hiagent-api=${HARBOR}/library/hiagent-api:${IMAGE_TAG}
                            kustomize edit set image hiagent-web=${HARBOR}/library/hiagent-web:${IMAGE_TAG}
                        """
                        
                        // 提交并推送
                        sh """
                            git add .
                            git commit -m "ci: update images to ${IMAGE_TAG} [skip ci]"
                            git push origin main
                        """
                    }
                }
            }
        }
    }
    
    post {
        success {
            echo "✅ 镜像已推送 Harbor, Git 清单已更新, ArgoCD 将自动同步"
        }
    }
}
```

### 数据流

```
1. 开发者 push 代码
2. Jenkins 触发构建 → 镜像推送到 Harbor
3. Jenkins 修改 Git 中 kustomization.yaml 的 images.newTag
4. Jenkins push 回 Git
5. ArgoCD 检测到 Git 变更（3分钟后自动轮询）
6. ArgoCD 自动 sync → K8s 滚动更新
```

---

## 方案2: GitLab（代码托管 + CI 平台） CI + ArgoCD 联动

### 架构

```
Git Push → GitLab Runner → Harbor(存镜像) → Git(更新tag) → ArgoCD(自动同步)
```

### 前提条件

- GitLab（自托管或 SaaS）
- GitLab Runner（已注册到集群）
- ArgoCD + Harbor 同上

### Step 1: ArgoCD Application（同方案1）

配置完全一样，ArgoCD 不关心谁构建的镜像。

### Step 2: .gitlab-ci.yml

```yaml
# .gitlab-ci.yml
stages:
  - validate
  - build
  - update-manifest

variables:
  HARBOR: "192.168.1.61"
  MANIFEST_REPO: "http://192.168.1.61:3000/root/hiagent-manifests.git"

before_script:
  - export IMAGE_TAG="${CI_COMMIT_SHORT_SHA}-${CI_PIPELINE_ID}"

# ============ 阶段1: 验证 ============
validate:
  stage: validate
  image: python:3.11-slim
  script:
    - pip install pyyaml
    - python scripts/validate-config.py
  only:
    - main
    - develop

# ============ 阶段2: 构建镜像 ============
build-images:
  stage: build
  image: docker:24-dind
  script:
    - docker login -u $HARBOR_USER -p $HARBOR_PASSWORD $HARBOR
    - |
      for svc in api web inference; do
        docker build -t ${HARBOR}/library/hiagent-${svc}:${IMAGE_TAG} -f ${svc}/Dockerfile .
        docker push ${HARBOR}/library/hiagent-${svc}:${IMAGE_TAG}
      done

# ============ 阶段3: 更新 Git 清单（联动关键）============
update-manifest:
  stage: update-manifest
  image: alpine/git:latest
  before_script:
    - apk add --no-cache kustomize
  script:
    - git clone https://gitlab-ci-token:${CI_JOB_TOKEN}@gitlab.com/your-org/hiagent-manifests.git
    - cd hiagent-manifests
    - git config user.email "gitlab-ci@hiagent.local"
    - git config user.name "GitLab CI"
    - |
      ENV_DIR="overlays/${CI_COMMIT_BRANCH == 'main' ? 'prod' : 'staging'}"
      cd manifests/${ENV_DIR}
      kustomize edit set image hiagent-api=${HARBOR}/library/hiagent-api:${IMAGE_TAG}
      kustomize edit set image hiagent-web=${HARBOR}/library/hiagent-web:${IMAGE_TAG}
      kustomize edit set image hiagent-inference=${HARBOR}/library/hiagent-inference:${IMAGE_TAG}
    - git commit -am "ci: update images to ${IMAGE_TAG} [skip ci]"
    - git push origin main
  environment:
    name: ${CI_COMMIT_BRANCH == 'main' ? 'production' : 'staging'}
```

### 数据流

```
1. 开发者 push 代码 → GitLab CI 自动触发
2. validate 阶段: YAML 配置校验
3. build 阶段: 构建 Docker 镜像并推送到 Harbor
4. update-manifest 阶段:
   - 克隆 manifests 仓库
   - kustomize edit set image 更新 tag
   - git push 回主分支
5. ArgoCD 检测到 Git 变更 → 自动同步
```

---

## 方案3: 纯 GitOps（无 CI 工具模式）

> ⚠️ **注意**：此处的"方案3"指的是 **无 CI 工具的部署模式**（开发者手动构建镜像 + ArgoCD 自动同步）。
> 项目中 `方案3-Argo-Rollouts/` 目录在此基础上增加了 **Argo Rollouts（渐进式发布控制器） 灰度发布**（金丝雀 + 蓝绿），
> 属于高级发布策略扩展，详见 [方案3 README](./方案3-Argo-Rollouts/README.md)。

### 架构

```
开发者手动构建镜像 → 推送到 Harbor → 更新 Git 中 image tag → ArgoCD 自动同步
```

### 特点

- **无 CI 工具**：不依赖 Jenkins / GitLab CI / GitHub Actions
- **Git 是唯一真相源**：一切变更通过 Git commit 驱动
- **最简单**：没有 Pipeline（流水线） 维护成本
- **适合场景**：小团队、配置型变更为主、镜像变更少

### Step 1: ArgoCD Application（同上）

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: hiagent
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  source:
    repoURL: http://192.168.1.61:3000/root/hiagent-manifests.git
    targetRevision: main
    path: manifests/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: hiagent
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Step 2: 开发者操作流程

```bash
# ===== 1. 本地构建镜像 =====
docker build -t 192.168.1.61/library/hiagent-api:v1.2.3 -f api/Dockerfile .
docker push 192.168.1.61/library/hiagent-api:v1.2.3

# ===== 2. 克隆 manifests 仓库 =====
git clone http://192.168.1.61:3000/root/hiagent-manifests.git
cd hiagent-manifests/manifests/overlays/prod

# ===== 3. 更新镜像 tag =====
kustomize edit set image hiagent-api=192.168.1.61/library/hiagent-api:v1.2.3

# ===== 4. 提交 Git =====
git add .
git commit -m "release: hiagent-api v1.2.3"
git push origin main

# ===== 5. ArgoCD 自动检测变更并同步（无需手动操作）=====
```

### 可选：编写简单的发布脚本减少手动操作

```bash
#!/bin/bash
# scripts/release.sh - 纯 GitOps 发布脚本（无 CI 工具依赖）
set -e

SERVICE=$1      # api / web / inference
VERSION=$2      # v1.2.3
HARBOR="192.168.1.61"
MANIFEST_REPO="http://192.168.1.61:3000/root/hiagent-manifests.git"
WORKDIR="/tmp/hiagent-release-$$"

# 1. 构建并推送
docker build -t ${HARBOR}/library/hiagent-${SERVICE}:${VERSION} -f ${SERVICE}/Dockerfile .
docker push ${HARBOR}/library/hiagent-${SERVICE}:${VERSION}

# 2. 更新 Git manifests
git clone ${MANIFEST_REPO} ${WORKDIR}
cd ${WORKDIR}/manifests/overlays/prod
kustomize edit set image hiagent-${SERVICE}=${HARBOR}/library/hiagent-${SERVICE}:${VERSION}
git add .
git commit -m "release(${SERVICE}): ${VERSION}"
git push origin main

# 3. 清理
rm -rf ${WORKDIR}

echo "✅ 已发布 hiagent-${SERVICE}:${VERSION} → ArgoCD 将自动同步"
```

### 数据流

```
开发者 → docker build + push → 手动更新 Git tag → git push → ArgoCD 自动同步
```

---

## 三套方案对比总结

| 对比维度 | Jenkins + ArgoCD | GitLab CI + ArgoCD | 无 CI（纯 GitOps（以 Git 为唯一真相源的运维模式）） |
|---------|-----------------|--------------------|-----------|
| **CI 工具** | Jenkins（自建） | GitLab CI（Runner） | 无 |
| **CD 工具** | ArgoCD | ArgoCD | ArgoCD |
| **触发方式** | 手动/定时/Webhook（准入/回调钩子） | Git Push 自动 | 手动 git push |
| **构建步骤** | Jenkinsfile 定义 | .gitlab-ci.yml 定义 | 开发者手动/脚本 |
| **复杂度** | ⭐⭐⭐ 中等 | ⭐⭐ 较低 | ⭐ 最低 |
| **适用场景** | 大型企业（已有 Jenkins） | GitLab 用户 | 小型项目/配置型变更 |
| **上手成本** | 需要配 Pipeline | GitLab Runner（GitLab CI 执行器） 即可 | 只需 ArgoCD |
| **灵活性** | 最高（Groovy 可编程） | 高（YAML + 自定义） | 低（只有 Git push） |
| **维护成本** | 高（Jenkins 运维） | 中（Runner 管理） | 低（无额外组件） |
| **当前环境就绪度** | ✅ Jenkins 已部署 | ⚠️ 需部署 Runner | ✅ ArgoCD 已部署 |

> 💡 **扩展阅读**：项目中的 `方案3-Argo-Rollouts/` 目录在"无 CI 模式"基础上增加了 **Argo Rollouts 高级发布策略**（金丝雀 + 蓝绿发布），将普通的 Deployment（部署，无状态工作负载） 替换为 Rollout 资源，适合需要精细控制发布节奏的场景。

---

## 当前可立即使用的方案

由于 Jenkins 和 ArgoCD 都已就绪，**方案 1 可立即落地**：

```
Harbor (192.168.1.61)  ←镜像构建/存储
Jenkins (jenkins.test)  ← CI Pipeline
ArgoCD (argocd.test)    ← CD 自动同步
K8s 集群 (5 nodes)      ← 部署目标
```

下一步我可以帮你：
1. 在 Jenkins 里创建实际可运行的 Pipeline Job
2. 或部署 GitLab Runner 实现方案 2
3. 或直接写好纯 GitOps 的发布脚本

选哪个？
