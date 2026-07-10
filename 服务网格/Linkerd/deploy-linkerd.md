# Linkerd 服务网格部署（离线 / Harbor 镜像）

> 版本：linkerd2 **stable-2.14.10**（CLI 与数据面同版本）
> 集群：kubeadm v1.28.15（5 节点，聚焦模式，master 内存红线 → 控制面只落 worker）
> 镜像源：cr.l5d.io/linkerd/* → 经 `外网资源同步/sync_from_us.ps1` 入 Harbor `192.168.1.61/linkerd/*`
> 验证结论：`linkerd check --proxy` 全绿；demo 注入 2/2；mTLS 生效；黄金指标可采。

## 1. 为什么选 stable-2.14.10 而不是最新 edge

- edge（如 edge-26.6.3）给 `linkerd-destination` / `linkerd-proxy-injector` 的 **proxy-init 初始化容器加了探针**，
  但 **k8s 1.28 不允许 init 容器带探针**（1.29+ 才允许），导致这两个 Deployment 创建失败、控制面不可用。
- stable-2.14.10 是兼容 k8s 1.28 的最后一个稳定版，无此问题。

## 2. 离线镜像清单（需同步进 Harbor）

控制面 + 数据面（registry 覆盖为 `192.168.1.61/linkerd`）：

```
cr.l5d.io/linkerd/controller:stable-2.14.10
cr.l5d.io/linkerd/proxy:stable-2.14.10
cr.l5d.io/linkerd/proxy-init:v2.2.3
cr.l5d.io/linkerd/policy-controller:stable-2.14.10
```

viz 扩展（同样覆盖为 `192.168.1.61/linkerd`）：

```
cr.l5d.io/linkerd/metrics-api:stable-2.14.10
cr.l5d.io/linkerd/tap:stable-2.14.10
cr.l5d.io/linkerd/web:stable-2.14.10
```

指标存储：

```
prom/prometheus:v2.48.0   →  192.168.1.61/prom/prometheus:v2.48.0
```

> ⚠️ 镜像同步坑：`sync_from_us.ps1` 的 `-HarborProject` 会与源镜像路径里的 org 叠加，
> 例如 `cr.l5d.io/linkerd/controller` + `-HarborProject linkerd` 会变成 `linkerd/linkerd/controller`（双路径）。
> 解决：同步后在 H1 用 `docker tag` 重打标到干净路径 `192.168.1.61/linkerd/<name>:<tag>` 再 push，并删除脏仓库。
> （`prom/prometheus` 的 subpath 本就是 `prometheus`，`-HarborProject prom` 直接落 `prom/prometheus`，无需重打标。）

## 3. 安装（离线渲染 + 应用）

Windows 侧用 `linkerd install --ignore-cluster` 离线生成清单（registry 指向 Harbor），推到 m1 后用 admin.conf apply：

```powershell
# 渲染（--registry 覆盖控制面/代理镜像前缀）
linkerd install --ignore-cluster --registry=192.168.1.61/linkerd > linkerd-control-plane.yaml
linkerd install --crds    --ignore-cluster                         > linkerd-crds.yaml
linkerd viz  install --ignore-cluster                            > linkerd-viz.yaml

# viz 镜像需手动改 registry（CLI 不支持 --registry 给 viz）：
#   cr.l5d.io/linkerd/{metrics-api,tap,web}:stable-2.14.10  -> 192.168.1.61/linkerd/<同名>:stable-2.14.10
#   prom/prometheus:v2.48.0                                 -> 192.168.1.61/prom/prometheus:v2.48.0

# 推到 m1 应用
scp linkerd-crds.yaml linkerd-control-plane.yaml linkerd-viz.yaml m1:/tmp/
ssh m1 "echo '123' | sudo -S bash -c 'export KUBECONFIG=/etc/kubernetes/admin.conf; \
  kubectl apply -f /tmp/linkerd-crds.yaml; \
  kubectl apply -f /tmp/linkerd-control-plane.yaml; \
  kubectl apply -f /tmp/linkerd-viz.yaml'"
```

> 控制面/代理默认不带 master taint 的 toleration，天然只调度到 worker，护住 master 内存红线。

## 4. 清理残留 webhook 的坑（重要）

若之前装过其他版本（如误装的 edge），`kubectl delete ns linkerd` 会**卡在 Terminating**——
因为残留的 `linkerd-proxy-injector-webhook-config` 等指向正在删除命名空间里的 service，删除回调不可达。
此时需先删 webhook 再清 finalizer：

```bash
for wh in linkerd-proxy-injector-webhook-config linkerd-policy-validator-webhook-config \
         linkerd-sp-validator-webhook-config linkerd-tap-injector-webhook-config; do
  kubectl delete mutatingwebhookconfiguration  "$wh" --ignore-not-found
  kubectl delete validatingwebhookconfiguration "$wh" --ignore-not-found
done
# 强制清 finalizer
kubectl get ns linkerd -o json | sed 's/"kubernetes"//' > /tmp/ld_ns.json
kubectl replace --raw /api/v1/namespaces/linkerd/finalize -f /tmp/ld_ns.json
```

## 5. 验证

```bash
# 全套健康检查（控制面 + 数据面 + 身份证书 + 指标）
linkerd check --proxy

# demo 应用（见 linkerd-demo.yaml，命名空间打 linkerd.io/inject: enabled）
kubectl apply -f linkerd-demo.yaml
# 注入后 Pod 为 2/2（app + linkerd-proxy），linkerd check 显示 MESHED 1/1、2/2
# linkerd stat deploy -n linkerd-demo  →  SUCCESS/RPS/LATENCY/TCP_CONN 黄金指标
```

## 6. 能力小结（对比 Istio 用）

| 维度 | Linkerd 表现 |
|------|------|
| mTLS | 默认全量 Pod 间 mTLS，数据面证书由 linkerd-identity 签发，check 显示证书匹配 CA |
| 注入 | 命名空间注解 `linkerd.io/inject: enabled`，自动注入 Rust 写的 ultra-light proxy |
| 黄金指标 | success / RPS / latency(p50,p95,p99) / TCP conn，Prometheus 已采集 |
| 观测 UI | linkerd-viz（web dashboard + tap 实时流量） |
| 资源占用 | 极低（Rust proxy，~10-20MB/sidecar），适合聚焦模式 |
| 流量治理 | 偏轻：retry / timeout / traffic-split（需 SMI CRD），无原生熔断/限流 |
| 熔断/限流 | 原生不支持，需配合外部组件 |
