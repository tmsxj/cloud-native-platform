# 供应链安全（第 24 项）

> 云原生 DevSecOps 的「供应链准入」闭环：**只准运行签名镜像**。
> 与已有的 Trivy 扫描、Kyverno（策略即代码引擎） 准入、Falco 运行时检测拼成完整 DevSecOps 四层。

## 做了什么
- **镜像签名**：`cosign（镜像签名工具）` 用本地私钥对镜像签名（[`cosign-sbom/sign-and-sbom.sh`](./cosign-sbom/sign-and-sbom.sh)）
- **SBOM（软件物料清单） 生成**：`syft` 生成软件物料清单，随镜像留存
- **准入验签**：`Kyverno` `verifyImages` 策略在 Pod（容器组） 准入时校验签名，**未签名镜像一律拒绝**
- **离线适配**：策略加 `rekor.ignoreTlog` / `ctlog.ignoreSCT` 跳过透明日志；本地仓库 CA 注入 Kyverno 准入控制器系统信任库

## 验证（闭环生效 ✅）
| 用例 | 结果 |
|------|------|
| 签名镜像 | `Running`（放行）|
| 未签名镜像 | 被 `require-signed-images` 拒绝：`no signatures found` |

## 目录
| 路径 | 说明 |
|------|------|
| [部署供应链安全.md](./部署供应链安全.md) | 完整部署文档（架构 / 步骤 / 闭环实测 / 踩坑三连击）|
| `cosign-sbom/` | cosign 签名 + SBOM 生成可复现脚本 |
| `kyverno-verify/` | 本地仓库 CA 注入清单（`kyverno-localreg-ca.yaml` + `ca-inject.sh`）|
| [`../策略即代码-Kyverno/policies/require-signed-images.yaml`](../策略即代码-Kyverno/policies/require-signed-images.yaml) | 签名验签策略 |
