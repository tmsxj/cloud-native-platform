# 服务网格对比演示：Linkerd（服务网格） vs Istio（第 23 项）

> 目的：在同一套 kubeadm 集群（v1.28.15，聚焦模式，master 内存红线）上**先后落地两套服务网格**，
> 用**完全相同的 demo 应用**（nginx-backend + client）对比两者在 mTLS（双向 TLS）、注入、L7 观测、流量治理上的差异。
> 控制面均只调度到 worker 节点，保护 master 内存。

## 0. 环境约束与统一做法

| 项 | 说明 |
|----|------|
| 集群 | kubeadm v1.28.15，5 节点（m1/m2/m3 master 带 NoSchedule；w1/w2 worker） |
| 镜像策略 | 一律 `外网资源同步/sync_from_us.ps1` → Harbor（私有镜像仓库） `192.168.1.61`；YAML 内 image 写 `192.168.1.61/<项目>/<镜像>:<tag>` |
| 控制面落点 | Linkerd / Istio 控制面 Deployment（部署，无状态工作负载） 无 master toleration，天然只落 worker |
| 模式 | 聚焦模式：全家桶 scale 0，仅控制面 + Cilium（基于 eBPF 的 CNI/网络方案） + MinIO + 网格在跑 |

## 1. 选型结论

| 维度 | Linkerd | Istio（服务网格） |
|------|---------|-------|
| 版本 | stable-2.14.10 | 1.30.2（profile=default） |
| 数据面 | Rust **proxy**（~10-20MB/sidecar） | C++ **Envoy（数据面代理）**（~50-100MB/sidecar） |
| 控制面 | destination / identity / proxy-injector | istiod（控制面）+ ingress-gateway |
| 资源占用 | 极低，聚焦模式首选 | 较重，但控制面只在 worker 可控 |
| 推荐场景 | 轻量、mTLS + 基础观测、资源紧张 | 重度流量治理、网关、多集群、L7 全功能 |

> Linkerd 未选 edge-26.6.3：其给 proxy-init init 容器加探针，k8s 1.28 不支持 init 容器探针（1.29+ 才行），导致控制面 Deployment 创建失败。

## 2. 相同 demo 应用

两个网格都用同一套应用，命名空间不同但结构一致：

| 组件 | Linkerd 命名空间 | Istio 命名空间 |
|------|------------------|----------------|
| 注入方式 | `linkerd.io/inject: enabled` | `istio-injection: enabled` |
| backend | `nginx-backend`（2 副本，image `192.168.1.61/library/nginx:alpine`） | 同左 |
| client | `client`（1 副本，busybox 循环请求 backend） | 同左 |

## 3. 验证结果对照

| 能力 | Linkerd（已验证） | Istio（已验证） |
|------|-------------------|-----------------|
| Sidecar（边车代理） 注入 | Pod 2/2（app + linkerd-proxy） | Pod 2/2（app + istio-proxy） |
| mTLS | `linkerd check --proxy` 显示数据面证书匹配 CA | PeerAuthentication **STRICT**；非网格明文直连 backend 被拒（Connection refused, exit 1） |
| L7 黄金指标 | success / RPS / latency(p50/p95/p99) / TCP conn（`linkerd stat deploy`） | `istio_requests_total`（90 请求全 200）+ request_duration P50/P90/P99 + request/response bytes |
| 观测入口 | linkerd-viz web + tap（已装） | 默认无 UI（需 Kiali/Grafana（可视化面板），本部署未装 addon；原始计数器已可采） |
| 重试/超时 | 需 SMI TrafficSplit/Retry CRD（轻） | VirtualService `retries/timeout` 原生支持（已下发） |
| 熔断/限流 | 原生不支持 | DestinationRule `outlierDetection` + `connectionPool`（已下发并生效） |
| 入口网关 | 需配合第三方 ingress | 自带 `istio-ingressgateway`（已 Running） |

## 4. 一句话总结（面试向）

- **Linkerd**：Rust 轻量 proxy，开箱即用的 mTLS + 黄金指标，资源占用极低，适合**快速获得零信任 + 基础可观测**；弱在流量治理（无原生熔断/限流）和入口网关。
- **Istio**：Envoy 全功能数据面 + istiod 控制面，原生支持**重试/超时/熔断/限流/入口网关/多集群**，适合**复杂流量治理与企业级场景**；代价是 sidecar 与控制面更重，运维复杂度更高。
- **选型口诀**：资源紧张 / 只要零信任 + 观测 → Linkerd；要流量治理全家桶 / 网关 / 多集群 → Istio。

## 5. 产物索引

- `Linkerd/`：`linkerd-crds.yaml` / `linkerd-control-plane.yaml` / `linkerd-viz.yaml` / `linkerd-demo.yaml` / `deploy-linkerd.md`
- `Istio/`：`istio-final.yaml`(渲染基线) / `istio-demo.yaml` / `istio-policy.yaml` / `deploy-istio.md`
- 本文件：双网格对比总览
