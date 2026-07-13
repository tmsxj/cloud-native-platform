# 第25项 密钥进阶：HashiCorp Vault + External Secrets Operator（外部密钥操作符，ESO）

把集群里的「密钥管理」从 K8s 原生 Secret（密钥对象） / Sealed Secrets 往前推一层，落地**企业级动态密钥管理**：
集中密钥库（Vault）通过 External Secrets Operator（操作符，自动化运维控制器） 自动把密钥同步成 K8s Secret，应用无感知、不改代码即可使用，且密钥不在 Git 中明文出现。

---

## 一、目标

- Vault（密钥管理系统） 作为集中密钥库，启用 KV v2 引擎存放密钥（如数据库密码）
- External Secrets Operator（ESO）连接 Vault，把指定密钥自动同步为 K8s（Kubernetes，容器编排引擎） 原生 Secret
- 形成闭环：**Vault 改密 → ESO 定时刷新 → K8s Secret 更新 → 应用热加载**

## 与原生 Secret / Sealed Secrets 的差异

| 维度 | K8s 原生 Secret | Sealed Secrets | Vault + ESO（本方案） |
|------|----------------|----------------|----------------------|
| 密钥是否明文入 Git | 是（base64 可还原） | 否（加密后入 Git） | 否（仅 Vault 持有明文，K8s 侧始终是解密后的 Secret） |
| 集中管理 | 否（各 ns 各自维护） | 否 | 是（Vault 统一存管） |
| 动态轮转 | 需手动改 | 需重新加密 | 自动：`refreshInterval` 拉取新值，应用热加载 |
| 审计 | 无 | 无 | Vault Audit Device 可追溯每次访问 |
| 适用 | 演示 | 私有化起步 | 企业级密钥治理 |

## 二、组件与镜像（离线 Harbor（私有镜像仓库））

| 组件 | 版本 | Harbor 镜像 |
|---|---|---|
| Vault | 1.19.4 | `192.168.1.61/hashicorp/vault:1.19.4` |
| External Secrets Operator | 0.18.1 | `192.168.1.61/oci.external-secrets.io/external-secrets/external-secrets:v0.18.1` |

> 镜像均通过 `外网资源同步/sync_from_us.ps1` 从外网拉取后推送到 Harbor（Vault 来自 `hashicorp/vault`，ESO 实际使用的是 `oci.external-secrets.io/external-secrets/external-secrets`，官方 install manifest 三个 Deployment（部署，无状态工作负载） 共用同一镜像）。

## 三、部署架构

```
                 ┌─────────────────────────────────────────────┐
                 │              Vault (dev 模式, vault ns)       │
                 │  kv-v2 @ kv/  →  kv/db : password=Sup3rS3cret! │
                 └───────────────▲─────────────────────────────┘
                                 │ http://vault.vault.svc:8200 (token auth: root)
                 ┌───────────────┴─────────────────────────────┐
                 │   External Secrets Operator (external-secrets ns)│
                 │  - controller      : 监听 ExternalSecret, 拉取并写入 K8s Secret │
                 │  - webhook         : 校验 SecretStore/ExternalSecret (自签证书)  │
                 │  - cert-controller : 为 webhook 自签/轮转证书(无需 cert-manager)  │
                 └───────────────┬─────────────────────────────┘
                                 │ SecretStore(vault-backend) + ExternalSecret(db-secret)
                 ┌───────────────┴─────────────────────────────┐
                 │  K8s Secret: db-secret (data.password)        │
                 │  → 应用 Pod 以 env/volume 挂载, 无感知使用      │
                 └─────────────────────────────────────────────┘
```

- **Vault** 用 dev 模式演示（自动 unseal，根 token 固定 `root`，内存存储，重启即丢）。生产见第八节。
- **ESO** 官方 install manifest 自带 `cert-controller`，webhook 证书自签，**不依赖 cert-manager**。
- 各组件放在独立命名空间：`vault`（Vault + 演示 Secret/ExternalSecret）、`external-secrets`（ESO 控制面）。

## 四、部署步骤

1. **同步镜像**（见 `外网资源同步/sync_from_us.ps1`）
2. **部署 Vault**：`kubectl apply -f vault.yaml`（Namespace + Deployment + Service（服务，集群内服务发现），dev 模式）
3. **部署 ESO**：`kubectl apply -f eso-install.yaml`（CRD + RBAC（基于角色的访问控制） + controller/webhook/cert-controller，镜像与 namespace 已改为离线/独立 ns）
4. **初始化 Vault**（进入 pod）：
   ```sh
   vault secrets enable -path=kv kv-v2
   vault kv put kv/db password="Sup3rS3cret!"
   ```
5. **创建 SecretStore + ExternalSecret**：`kubectl apply -f eso-demo.yaml`
   - `vault-token` Secret 存 Vault 根 token
   - `SecretStore/vault-backend` 指向 `http://vault.vault.svc:8200`，path=`kv`，token auth
   - `ExternalSecret/db-secret` 把 `kv/db.password` 同步为 K8s Secret `db-secret`

## 五、踩坑实录（重点）

离线 + 严格 Kyverno（策略即代码引擎） 安全基线环境下，官方 manifest 不能直接 apply，依次解决了三类问题：

### 坑1：Kyverno 镜像仓库放行规则写死 `:5000`
`restrict-image-registries` 策略的 pattern 是 `192.168.1.61:5000/* | ghcr.io/*`，但集群实际从 `192.168.1.61/<项目>`（无端口，已验证 falco 以此地址正常 pull）拉镜像。所有新建负载（含 Vault/ESO）因此被拒。
**修复**：把放行规则改为 `192.168.1.61/* | 192.168.1.61:5000/* | ghcr.io/*`，与实际拉取地址一致。

### 坑2：Kyverno 安全基线与第三方官方 manifest 冲突
`disallow-privileged`（容器需显式 `privileged: false`）、`require-probes`（容器需 liveness/readiness Probe）、`require-signed-images`（未签名镜像拒绝）三个策略拦截了 ESO/Vault 官方配置。
**修复**：对 `external-secrets`、`vault` 两个命名空间在对应策略加 exclude（演示组件豁免，业务负载仍强制）。Vault 的 Deployment 因此在豁免后立即创建成功。

### 坑3：ESO 改 namespace 后漏改命令行参数，webhook 崩溃
把 manifest 里 `namespace: default` 全部替换为 `external-secrets` 后，ESO 三个 pod 起来了，但 webhook 反复 CrashLoop。排查发现 cert-controller 的 `--secret-namespace=default`、`--service-namespace=default` 以及 webhook 的 `--dns-name=external-secrets-webhook.default.svc` 是**命令行参数**，未被 `namespace:` 字段替换，仍指向 default。结果 cert-controller 往 default ns 写证书，而 webhook 挂载的是 external-secrets ns 里**空的** `external-secrets-webhook` secret（DATA=0）→ webhook 启动崩溃。
**修复**：把这三处参数改为 `external-secrets` / `external-secrets-webhook.external-secrets.svc`，重新 apply 后 cert-controller 正确写入证书，webhook 1/1 Running。

> 经验：用脚本批量替换 `namespace: default` 时，务必同时处理同文件里以命令行参数形式出现的 namespace（如 `--xxx-namespace=default`、`*.default.svc`）。

## 六、验证结果

```sh
$ kubectl get externalsecret -n vault
NAME        STORETYPE     STORE           REFRESH INTERVAL   STATUS         READY
db-secret   SecretStore   vault-backend   1m                 SecretSynced   True

$ kubectl get secret db-secret -n vault -o jsonpath='{.data.password}' | base64 -d
Sup3rS3cret!      # 与 Vault kv/db 中写入的值完全一致
```

闭环成立：Vault 中的密钥已自动同步为 K8s Secret，且 `ExternalSecret` 状态为 `SecretSynced / Ready`。

## 七、应用挂载示例

应用无需感知 Vault，直接挂 K8s Secret 即可（与用原生 Secret 完全一致）：

```yaml
env:
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: db-secret
      key: password
```

ESO 默认 `refreshInterval: 1m`，Vault 中改密后最多 1 分钟自动刷新到 K8s Secret，应用热加载即可拿到新值（滚动重启或支持动态读取的客户端可零中断）。

## 八、生产建议

- **Vault 不要再用 dev 模式**：改用 Raft（Integrated Storage）或 Consul 后端做持久化；用 **auto-unseal**（Transit/KMS）避免手动 unseal；根 token 与 unseal key 用外部机密管理，禁止固定 `root`。
- **ESO 高可用**：controller/webhook 可多副本；跨命名空间复用密钥时用 `ClusterSecretStore`，避免每个 ns 重复定义。
- **与第24项供应链安全结合**：Vault 镜像走 cosign（镜像签名工具） 签名 + Kyverno `verifyImages` 验签；Vault 中存放的密钥本身也可加密（transit 引擎）；ESO 拉取的 Secret 同样经过集群准入校验。
- **审计**：Vault 开 Audit Devices，所有密钥访问可追溯，补全 DevSecOps 审计一环。
