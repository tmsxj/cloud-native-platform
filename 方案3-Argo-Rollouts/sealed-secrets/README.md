# Sealed Secrets — Git 安全密钥管理

> **状态**: 配置就绪，待镜像搬运后部署 | **依赖**: Harbor 中有 `sealed-secrets-controller` 镜像

---

## 它解决什么问题

```
之前:  Secret (base64) → 不能安全存 Git → 手动 kubectl apply → 跟 GitOps 脱节
之后:  SealedSecret (加密) → 可安全提交 Git → ArgoCD 同步 → 控制器自动解密为 Secret
```

---

## 工作原理

```
┌──────────────────────────────────────────────────────────────┐
│                        Sealed Secrets 工作流                   │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  1. 管理员执行:                                                │
│     kubeseal < secret.yaml > sealed-secret.yaml               │
│                     ↓ 用集群公钥加密                           │
│                                                               │
│  2. 提交 Git:                                                 │
│     git add sealed-secret.yaml && git push                    │
│                     ↓ ArgoCD 检测到变更                        │
│                                                               │
│  3. ArgoCD 同步到 K8s:                                        │
│     SealedSecret CRD → Controller 用私钥解密 → 生成 Secret    │
│                                                               │
│  4. 应用使用:                                                 │
│     Pod 挂载 Secret (跟普通 Secret 一样用)                     │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

**关键**: 只有集群内 Controller 持有私钥，即使 SealedSecret YAML 泄露也无妨。

---

## 部署步骤

### Step 1: 搬运镜像到 Harbor

集群节点无法访问外网，需要从有网络的机器把镜像推到 Harbor:

```bash
# 在能同时访问 docker.io 和 192.168.1.61 的机器上执行
bash push-image.sh
```

脚本内容:
```bash
docker pull docker.io/bitnami/sealed-secrets-controller:0.27.1
docker tag docker.io/bitnami/sealed-secrets-controller:0.27.1 192.168.1.61/library/sealed-secrets-controller:0.27.1
docker push 192.168.1.61/library/sealed-secrets-controller:0.27.1
```

### Step 2: 部署 Controller

```bash
kubectl apply -f controller.yaml
```

验证:
```bash
kubectl get pods -n kube-system -l name=sealed-secrets-controller
kubectl logs -n kube-system -l name=sealed-secrets-controller
```

### Step 3: 安装 kubeseal CLI

```bash
# Linux/macOS
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.1/kubeseal-linux-amd64
chmod +x kubeseal-linux-amd64 && sudo mv kubeseal-linux-amd64 /usr/local/bin/kubeseal

# Windows (PowerShell)
Invoke-WebRequest -Uri "https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.1/kubeseal-windows-amd64.exe" -OutFile "C:\tools\kubeseal.exe"
```

### Step 4: 加密 Secret

```bash
# 1. 获取 Controller 公钥 (自动从 K8s API 获取)
kubeseal --fetch-cert --controller-name=sealed-secrets-controller --controller-namespace=kube-system

# 2. 加密一个 Secret
kubeseal --controller-name=sealed-secrets-controller --controller-namespace=kube-system \
  < example-secret.yaml > sealed-harbor-registry.yaml

# 3. 查看加密后的内容 (全是加密乱码，安全!)
cat sealed-harbor-registry.yaml

# 4. 提交到 Git
git add sealed-harbor-registry.yaml && git commit -m "Add sealed harbor registry secret" && git push
```

### Step 5: ArgoCD 自动同步

ArgoCD 检测到 Git 变更后自动 sync → Controller 解密 SealedSecret → 生成普通 Secret → Pod 可以使用。

---

## 文件说明

| 文件 | 用途 |
|------|------|
| `controller.yaml` | Controller 部署清单 (已改为 Harbor 镜像) |
| `push-image.sh` | 镜像搬运脚本 (从 docker.io → Harbor) |
| `example-secret.yaml` | 明文 Secret 模板 (不要提交 Git) |
| `sealed-harbor-registry.yaml` | 加密后的 SealedSecret 示例 (可安全提交) |
| `README.md` | 本文档 |

---

## 三套方案中的集成方式

```
方案1 (Jenkins):  Jenkins Pipeline 不碰密钥 → 密钥由 SealedSecret 管理 → ArgoCD 同步
方案2 (GitLab CI): .gitlab-ci.yml 中引用 SealedSecret 管理的凭据
方案3 (Argo Rollouts): kustomization.yaml 中 patchesStrategicMerge 引用 SealedSecret
```

所有方案共用同一套 Sealed Secrets 基础设施，无需为每种 CI 工具单独配置密钥。

---

## 最佳实践

1. **SealedSecret 放 Git** — 加密后安全，跟代码一起版本管理
2. **明文 Secret 不提交** — `.gitignore` 中排除 `*-secret.yaml` 但保留 `sealed-*.yaml`
3. **按命名空间隔离** — 每个 ns 创建独立的 SealedSecret
4. **Controller 部署在 kube-system** — 基础组件统一管理
5. **定期轮换密钥** — `kubeseal --rotate` 可重新加密

---

## 与云厂商方案的对比

| | Sealed Secrets | 云厂商 (SSM/KMS) | HashiCorp Vault |
|---|---|---|---|
| 费用 | 免费 | 按 API 调用计费 | 免费社区版 |
| 外网依赖 | 无 | 需要 | 需要 |
| 复杂度 | ⭐ | ⭐⭐ | ⭐⭐⭐⭐ |
| GitOps 兼容 | ✅ 天然兼容 | 需 External Secrets Operator | 需额外集成 |
| 适用场景 | 内网自建 K8s | 公有云 K8s | 大型企业多集群 |
