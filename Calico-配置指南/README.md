# Calico 配置指南

> 创建日期：2026-07-09
> 定位：成熟稳定的 CNI / 网络策略引擎（NetworkPolicy）
> 适用：传统 / 保守生产环境、节点内核受限、客户指定 Calico、需 NetworkPolicy 零信任
> 说明：本项目集群当前实际由 Cilium 接管网络，Calico 仅作**资料沉淀**；本目录为独立生产指导方案，不与运行态绑定。

---

## 目录导航

| 文件 | 内容 |
|:---|:---|
| `Calico-生产配置详解.md` | IPPool 规划 / 封装模式 / BPF 数据面 / 策略 / Typha / 资源 |
| `故障排查手册.md` | 网络不通、Pod 无 IP、策略失效等定位 |

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
| 需要 Service LB | 保留 kube-proxy（BPF 模式下可去 kube-proxy） |

## 与 Cilium 的关系

- 两者**同一集群同一时刻只能有一个真正接管 Pod 网络**（kubelet 按 CNI 配置文件名字典序加载）。
- 选型与对比见 `../CNI总览/CNI-生产配置对比.md`。
- 本项目 CI/CD、可观测性全家桶均不依赖特定 CNI，切换 CNI 不影响上层负载。
