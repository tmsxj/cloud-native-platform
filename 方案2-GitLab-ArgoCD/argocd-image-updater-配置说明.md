# ArgoCD Image Updater 配置说明

> 方案2 GitLab-ArgoCD 的 CD 引擎：取代传统 `sed + git push` 部署方式的自动化镜像更新方案

---

## 一、为什么需要 Image Updater？

| 传统方式 (方案1 Jenkins) | Image Updater 方式 (方案2 GitLab) |
|---|---|
| CI 用 `sed` 修改 YAML → `git commit` → `git push` | CI 只管构建+推送镜像 |
| ArgoCD 检测 Git 变更 → 自动同步 | Image Updater 检测 Harbor 新镜像 → 更新 ArgoCD 参数 → 触发同步 |
| Git 仓库有大量 CI 提交噪音 | Git 仓库保持干净 |
| CI 需要 Git 写权限 | CI 只需要 Harbor 写权限 |

---

## 二、集群部署架构

```
┌─────────────────────────────────────────────────────────────┐
│                    argocd namespace                          │
│                                                              │
│  ┌──────────────────────┐    ┌───────────────────────────┐  │
│  │ argocd-image-updater │    │ argocd-image-updater-config│  │
│  │ Deployment (v0.14.0) │◀───│ ConfigMap                  │  │
│  │                      │    │  - registries.conf         │  │
│  │  ENV:                │    │  - argocd.server_addr      │  │
│  │  - ARGOCD_TOKEN      │    │  - log.level: debug        │  │
│  │  - ARGOCD_INSECURE   │    └───────────────────────────┘  │
│  │  - ARGOCD_PLAINTEXT  │                                    │
│  └──────────┬───────────┘    ┌───────────────────────────┐  │
│             │                │ argocd-image-updater-secret│  │
│             │                │  - argocd.token            │  │
│             │                └───────────────────────────┘  │
│             │                                                 │
│             ▼                                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              ArgoCD Application: tomcat-dev            │   │
│  │                                                        │   │
│  │  Annotations:                                          │   │
│  │  ├─ image-list: tomcat-app=192.168.1.61/.../tomcat-app │   │
│  │  ├─ tomcat-app.update-strategy: latest                 │   │
│  │  └─ write-back-method: argocd                          │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 三、ConfigMap 配置详解

```yaml
# argocd-image-updater-config
data:
  # ArgoCD API 连接 (内网 gRPC 明文通信)
  argocd.server_addr: argocd-server.argocd.svc.cluster.local  # K8s 内部 DNS
  argocd.insecure: "true"      # 不验证 TLS
  argocd.plaintext: "true"     # 不使用 TLS 加密 (内网环境)

  # 日志级别: debug 可看到每次检测的镜像变化
  log.level: debug

  # Harbor 注册表配置
  registries.conf: |
    registries:
    - name: Harbor
      api_url: http://192.168.1.61    # Harbor API 地址
      prefix: 192.168.1.61            # 镜像前缀匹配
      insecure: true                  # HTTP 访问 (内网)
      default: true                   # 设为默认注册表
      ping: false                     # 不检测连通性
```

---

## 四、Application 注解说明

在 ArgoCD Application 中添加以下注解即可启用自动镜像更新：

```yaml
metadata:
  annotations:
    # 定义要监控的镜像列表: <别名>=<registry>/<project>/<image>
    argocd-image-updater.argoproj.io/image-list: tomcat-app=192.168.1.61/tomcat-demo/tomcat-app

    # 更新策略:
    # - latest: 始终用最新推送的镜像
    # - semver: 语义化版本
    # - name: 按 tag 名称字母排序
    argocd-image-updater.argoproj.io/tomcat-app.update-strategy: latest

    # 写回方式:
    # - argocd: 更新 Application .spec.source.kustomize.images 字段 (推荐)
    # - git: 修改 Git 仓库中的文件 (需要 Git 写权限)
    argocd-image-updater.argoproj.io/write-back-method: argocd
```

**工作原理**：
1. Image Updater 每 2 分钟轮询 Harbor API: `GET /api/v2.0/projects/tomcat-demo/repositories/tomcat-app/artifacts`
2. 发现新镜像标签 → 更新 ArgoCD Application 的 `kustomize.images` 参数
3. ArgoCD 检测到 Application 变更 → 触发自动同步 → K8s 滚动更新

---

## 五、与 .gitlab-ci.yml 的分工

```
┌───────────────────────────────────────────────────────────┐
│  .gitlab-ci.yml (CI)          │  Image Updater (CD)       │
├───────────────────────────────┼───────────────────────────┤
│  Stage 1: unit-test           │                           │
│  Stage 2: checkstyle+spotbugs │                           │
│  Stage 3: build WAR           │                           │
│  Stage 4: docker-build        │                           │
│  Stage 5: docker-push         │  ← 检测到新镜像!          │
│  Stage 6: trivy-scan          │                           │
│                               │  更新 Application 参数    │
│                               │  触发 ArgoCD Sync         │
│                               │  滚动更新 K8s Deployment  │
└───────────────────────────────┴───────────────────────────┘
```

**核心设计理念**：CI 只负责"构建+验证+推送"，CD 完全交给 GitOps 引擎。

---

## 六、当前集群状态验证

```bash
# 查看 Image Updater 运行状态
kubectl -n argocd get pods -l app.kubernetes.io/name=argocd-image-updater

# 查看日志 (debug 模式会显示每次检测)
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-image-updater --tail=50

# 查看 ArgoCD Application 上的 Image Updater 注解
kubectl -n argocd get application tomcat-dev -o yaml | grep -A5 'argocd-image-updater'

# 验证 Kustomize images 参数 (Image Updater 实际修改的位置)
kubectl -n argocd get application tomcat-dev -o jsonpath='{.spec.source.kustomize.images}'
```

**当前状态**：
- Image Updater Pod: ✅ Running (argocd-image-updater-d9ff7bd4-f9jzv)
- ConfigMap: ✅ Harbor 注册表已配置
- Secret: ✅ ArgoCD Token 已注入
- Application: ✅ tomcat-dev 已添加 Image Updater 注解
- 当前镜像: `192.168.1.61/tomcat-demo/tomcat-app:v58-5ea9925f`

---

## 七、面试速答模板

**问**："你们的 CD 是怎么做的？"

**答**：
> 我们用了 ArgoCD Image Updater 实现全自动 CD。CI 做完 `docker push` 后，Image Updater 每 2 分钟轮询一次 Harbor API，检测到新镜像 tag 后自动更新 ArgoCD Application 的 kustomize images 参数，触发 ArgoCD 自动同步到 K8s。相比传统的 `sed + git push` 方式，有三个好处：
> 1. Git 仓库没有 CI 提交噪音
> 2. CI 不需要 Git 写权限，降低安全风险
> 3. 配置收敛——就是几行 Annotation，不需要额外写 CD 脚本

**问**："怎么保证只推送到正确环境？"

**答**：
> 我们为 dev/staging/prod 三个环境各自创建了独立的 ArgoCD Application，每个 Application 的 `update-strategy` 注解不同：
> - dev: `latest`（自动跟踪最新）
> - staging: `semver`（只自动更新补丁版本）
> - prod: 不开启自动更新（手动审批）

---

## 八、故障排查

| 症状 | 原因 | 排查命令 |
|------|------|----------|
| Image Updater 不检测 | ArgoCD Token 过期 | `kubectl -n argocd logs -l app.kubernetes.io/name=argocd-image-updater \| grep -i error` |
| 检测到新镜像但不更新 | Application 注解缺失 | `kubectl -n argocd get app tomcat-dev -o yaml \| grep argocd-image-updater` |
| Harbor 连不上 | 网络策略/防火墙 | `kubectl -n argocd exec -ti deploy/argocd-image-updater -- wget -qO- http://192.168.1.61/api/v2.0/health` |
| 更新后不生效 | ArgoCD sync 失败 | `kubectl -n argocd get app tomcat-dev` 查看 Sync Status |
