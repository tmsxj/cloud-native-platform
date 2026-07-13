# Calico（CNI/网络策略方案） 配置指南

> 创建日期：2026-07-09
> 定位：成熟稳定的 CNI（容器网络接口） / 网络策略引擎（NetworkPolicy）
> 适用：传统 / 保守生产环境、节点内核受限、客户指定 Calico、需 NetworkPolicy 零信任
> 说明：本项目集群当前实际由 Cilium（基于 eBPF 的 CNI/网络方案） 接管网络，Calico 仅作**资料沉淀**；本目录为独立生产指导方案，不与运行态绑定。

---

## 目录导航

| 文件 | 内容 |
|:---|:---|
| `Calico-生产配置详解.md` | IPPool 规划 / 封装模式 / BPF 数据面 / 策略 / Typha / 资源 |
| `故障排查手册.md` | 网络不通、Pod（容器组） 无 IP、策略失效等定位 |

## 架构总览

```
Pod ──> Calico CNI ──> (BPF 或 iptables 数据面) ──> 节点路由 / BGP
                        └──> Felix ──> NetworkPolicy 下发
            Typha(大规模) ──> 缓存 API server 状态，减轻其压力
```

## 生产决策速查

| 场景 | 推荐配置 |
|:---|:---|
| 小规模 / 简单网络 | iptables 数据面 + IPIP `cross-subnet` |
| 性能优先 | **BPF 数据面**（Calico v3.13+，去 iptables） |
| 大规模（>50 节点） | 启用 **Typha** |
| 跨子网合规加密 | **WireGuard** |
| 需要 Service（服务，集群内服务发现） LB | 保留 kube-proxy（BPF 模式下可去 kube-proxy） |

## 与 Cilium 的关系

- 两者**同一集群同一时刻只能有一个真正接管 Pod 网络**（kubelet 按 CNI 配置文件名字典序加载）。
- 选型与对比见 `../CNI总览/CNI-生产配置对比.md`。
- 本项目 CI/CD（持续集成/持续交付）、可观测性全家桶均不依赖特定 CNI，切换 CNI 不影响上层负载。

## Calico vs Cilium 选型对比

| 维度 | Calico | Cilium（本项目实际接管） |
|------|--------|------------------------|
| 数据面 | iptables 或 BPF（v3.13+） | eBPF（内核可编程技术） 原生 |
| 网络策略 | NetworkPolicy + 扩展（GlobalNetworkPolicy） | NetworkPolicy + 基于身份（Endpoint Identity） |
| 可观测 | 依赖外部（Prometheus + 自配） | 内置 Hubble，L3-L7 流可视化 |
| 服务网格/七层 | 需配合 Envoy 等 | 内建 L7（Envoy 集成）、ClusterMesh 多集群 |
| 性能 | BPF 模式去 iptables，较好 | eBPF 零 iptables，大规模更优 |
| 本项目定位 | 资料沉淀、保守/客户指定场景 | 当前运行态 CNI |

> 选型口诀：要 Hubble 流观测 + eBPF 性能 + 多集群 → Cilium；客户强指定 Calico / 内核受限 → 用本目录方案。
