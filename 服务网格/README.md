# 服务网格（Service Mesh）总览

> 第 23 项：在同一套 kubeadm 集群上**先后落地两套服务网格**，用相同 demo 对比 mTLS（双向 TLS）、注入、L7 观测与流量治理差异。
> 控制面均只调度到 worker 节点，保护 master 内存红线。

## 目录

| 路径 | 说明 |
|------|------|
| [`服务网格对比-Linkerd-vs-Istio.md`](./服务网格对比-Linkerd-vs-Istio.md) | 双网格选型结论 + 验证结果对照（核心文档） |
| `Linkerd/` | Linkerd stable-2.14.10：CRDs / 控制面 / viz / demo YAML + 部署手册 |
| `Istio/` | Istio 1.30.2：渲染基线 / demo / 策略（STRICT mTLS、重试超时、熔断）YAML + 部署手册 |

## 一句话选型

- **Linkerd**：Rust 轻量 proxy，开箱即用的 mTLS + 黄金指标，资源占用极低 → 资源紧张 / 只要零信任 + 基础观测。
- **Istio**：Envoy 全功能数据面 + istiod 控制面，原生重试/超时/熔断/限流/入口网关/多集群 → 复杂流量治理与企业级场景。

> 详细对比与验证数据见 [`服务网格对比-Linkerd-vs-Istio.md`](./服务网格对比-Linkerd-vs-Istio.md)。
