# CNI 生产配置对比（Cilium vs Calico（CNI/网络策略方案））

> 创建日期：2026-07-09
> 目的：面对不同生产环境时，快速选型 CNI（容器网络接口） 并定位所需配置调整
> 配套：`../eBPF-可观测性/Cilium（基于 eBPF 的 CNI/网络方案）-生产配置指南.md`、`../eBPF-可观测性/故障排查手册.md`、`../Calico-配置指南/`

---

## 一、核心对比

| 维度 | Calico | Cilium |
|:---|:---|:---|
| 数据面 | iptables / **BPF**（v3.13+） | **eBPF（内核可编程技术） 原生** |
| 内核要求 | 低（iptables 模式） | ≥5.4（推荐 ≥5.10） |
| 网络策略 | NetworkPolicy + 扩展 | L3/L4/**L7（HTTP/DNS 感知）** |
| 可观测性 | 较弱（需外部） | **Hubble 强**（七层流量图） |
| Service（服务，集群内服务发现） 负载均衡 | kube-proxy（BPF 模式可去） | **去 kube-proxy**（eBPF） |
| 性能天花板 | BPF 模式尚可 | eBPF 最高 |
| 成熟度 / 接受度 | 极高（金融等传统客户常用） | CNCF 毕业，新平台主流 |
| 跨节点加密 | WireGuard | WireGuard / IPsec |

## 二、选型建议

- **传统 / 保守 / 内核受限 / 客户指定** → Calico（iptables 或 BPF 模式）
- **云原生新平台 / 性能 / 七层可观测 / 去 kube-proxy** → Cilium
- **合规加密** → 两者均支持 WireGuard，按需开启

## 三、运行态关键约束

> **同一集群同一时刻只能有一个 CNI 真正接管 Pod（容器组） 网络。**
> kubelet 按 CNI 配置文件名字典序加载（如 `05-cilium.conflist` 先于 `10-calico.conflist`）。

本项目现状（2026-07-09，以节点 `/etc/cni/net.d` 为准）：
- Cilium **已实际接管 CNI**（`05-cilium.conflist` 生效，VXLAN 隧道模式），`kubeProxyReplacement=false` 故 **kube-proxy 仍保留**
- Calico 配置已被 Cilium 安装器备份为 `10-calico.conflist.cilium_bak`（停用态）；原 `calico-node` Pod 的 CNI 角色已失效
- `cni.enabled=false` 仅表示 chart 不管理 CNI 配置，节点上的 Cilium CNI 来自更早部署状态，重新 `helm upgrade` 不会删除已存在的 `05-cilium.conflist`
- 全家桶（ES/Prometheus（指标监控系统）/Tomcat 等）不依赖特定 CNI，切换无影响；回退依据见 `../eBPF-可观测性/backup/`

## 四、从 Calico 迁移到 Cilium（完整接管）步骤

1. 备份 Calico CNI 配置（`backup/calico-cni-before-cilium.conflist` 已留底）
2. 按 `Cilium-生产配置指南.md` 第三节改 values：`kubeProxyReplacement=true`、`cni.enabled=true`
3. 删除 Calico：`kubectl delete -f calico.yaml`（或对应 DaemonSet / Deployment（部署，无状态工作负载） / CRD）
4. 重装机或滚动重启节点，使 Cilium 接管
5. `cilium status --verbose` 全绿、`cilium connectivity test` 通过
6. 验证业务 Pod 网络与 Service 正常

## 五、反向（Cilium → Calico）

思路对称：禁用 Cilium 接管 → 部署 Calico（按 `Calico-配置指南/`）→ 滚动重启节点 → 校验。
