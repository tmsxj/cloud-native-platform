# P0.3 — Sealed Secrets 落地实操

> 📅 2026-07-05 完成 | 验证状态: ✅ 加密→解密→注入 Pod（容器组） 全链路通过

## 做了什么

1. 部署 Sealed Secrets Controller（kubeseal + controller）
2. 用 `kubeseal` CLI 加密 Harbor（私有镜像仓库） 镜像拉取凭据
3. 生成 SealedSecret CR → Controller 自动解密 → 注入目标命名空间 Secret（密钥对象）
4. Pod 使用解密后的 Secret 从 Harbor 拉取镜像验证

## 核心流程

```
Harbor 凭据 (明文)
    │
    ▼ kubeseal --cert <controller-pubkey>
SealedSecret CR (加密, 可入 Git)
    │
    ▼ kubectl apply → Controller 监听到
Secret (解密, 仅集群内可见)
    │
    ▼ Deployment → imagePullSecrets
Pod 启动，从 Harbor 拉取镜像
```

## 验证方式

```bash
# 1. 从 Harbor 创建 registry secret
kubectl create secret docker-registry harbor-creds \
  --docker-server=192.168.1.61 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  -n tomcat-prod --dry-run=client -o json \
  | kubeseal --format=yaml > harbor-creds-sealed.yaml

# 2. 部署 SealedSecret
kubectl apply -f harbor-creds-sealed.yaml

# 3. 验证自动解密
kubectl get secret harbor-creds -n tomcat-prod

# 4. Pod 挂载
# Deployment spec:
#   imagePullSecrets:
#     - name: harbor-creds
```

## 密钥管理方案对比（本项目两条路线）

| 维度 | Sealed Secrets（本文件） | External Secrets Operator + Vault（见 `../密钥进阶/部署Vault与ESO.md`） |
|------|--------------------------|----------------------------------------|
| 核心理念 | 加密后 Secret 入 Git，集群内自动解密 | 集中密钥库（Vault）定时同步成 K8s Secret |
| 外部依赖 | 无（纯 K8s native） | 需部署 Vault + ESO 控制面 |
| 密钥来源 | 静态凭据（如 Harbor 拉取口令） | 动态密钥（KV v2，支持轮转/自动刷新） |
| 适用场景 | 私有化最简、凭据不常变 | 企业级、密钥需集中管理与轮转 |
| 本项目角色 | 快速落地、零依赖起步 | 进阶路线，密钥不在 Git 明文出现 |

## 面试要点

1. **为什么不用 SOPs/External Secrets?** Sealed Secrets 零外部依赖，纯 K8s（Kubernetes，容器编排引擎） native，私有化部署最简方案
2. **加密密钥管理**: controller 启动时自动生成 RSA 密钥对，私钥在集群内，公钥供 kubeseal 加密
3. **安全边界**: SealedSecret 可入 Git，但只有目标集群 controller 能解密（namespace + name 绑定防重放）
4. **私钥备份**: `kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key`
