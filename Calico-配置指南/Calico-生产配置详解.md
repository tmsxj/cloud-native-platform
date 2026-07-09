# Calico 生产配置详解

> 创建日期：2026-07-09
> 定位：成熟稳定的 CNI / 网络策略引擎（NetworkPolicy），本项目已做**集群内真实切换验证**
> 与本项目关系：集群当前由 Calico 接管 CNI（实践切换所得）；本目录为独立生产指导方案。
> 配套：`README.md`（导航/架构/选型）、`故障排查手册.md`（踩坑速查）

---

## 一、何时选 Calico

- 传统 / 保守生产环境、节点内核受限、客户指定 Calico
- 需要稳定的 NetworkPolicy 零信任（L3/L4，k8s 原生策略）
- 大规模集群用 **Typha** 减轻 API server 压力
- 跨子网合规加密用 **WireGuard**（本项目未启用）

## 二、生产前置条件

| 项 | 要求 |
|:---|:---|
| 内核 | ≥3.10（iptables 数据面）；BPF 数据面需 ≥5.10（v3.13+） |
| 架构 | amd64 / arm64 |
| 冲突 CNI | 安装前必须移除其他 CNI 配置与 DaemonSet（如 Cilium） |
| kube-proxy | 保留（iptables 模式）；BPF 数据面下可去 kube-proxy |
| 封装 | 跨子网用 IP-in-IP 或 VXLAN；同二层可直连（CrossSubnet / Never） |

## 三、本项目集群真实部署值（已验证）

> 以下均来自 `2026-07-09` 在 5 节点 K3s 集群（m1/m2/m3 + w1/w2）上的真实切换与 `kubectl` 核查。

### 3.1 IPPool（IP 地址规划）

```bash
kubectl get ippool default-ipv4-ippool -o yaml
```

```yaml
apiVersion: crd.projectcalico.org/v1
kind: IPPool
metadata:
  name: default-ipv4-ippool
spec:
  cidr: 10.244.0.0/16          # Pod CIDR 总段
  blockSize: 26                # 每节点分配 /26（64 IP），避免 IP 浪费
  ipipMode: Always             # 跨节点走 IP-in-IP 封装（隧道设备 tunl0）
  vxlanMode: Never             # 不启用 VXLAN
  natOutgoing: true            # 出集群流量做 SNAT
  nodeSelector: all()          # 适用于所有节点
  allowedUses:
  - Workload
  - Tunnel
```

### 3.2 CNI 配置文件（节点 `/etc/cni/net.d/10-calico.conflist`）

```json
{
  "name": "k8s-pod-network",
  "cniVersion": "0.3.1",
  "plugins": [
    {
      "type": "calico",
      "log_level": "info",
      "log_file_path": "/var/log/calico/cni/cni.log",
      "datastore_type": "kubernetes",
      "nodename": "master1",
      "mtu": 0,
      "ipam": { "type": "calico-ipam" },
      "policy": { "type": "k8s" },
      "kubernetes": { "kubeconfig": "/etc/cni/net.d/calico-kubeconfig" }
    },
    { "type": "portmap", "snat": true, "capabilities": { "portMappings": true } },
    { "type": "bandwidth", "capabilities": { "bandwidth": true } }
  ]
}
```

### 3.3 控制面组件

| 组件 | 部署 | 状态 |
|:---|:---|:---|
| `calico-node` | DaemonSet（`kube-system`），每节点 1 个 | 5/5 `1/1 Running`（切换后重启次数稳定，不再崩溃循环） |
| `calico-kube-controllers` | Deployment | 负责 IPAM / CRD 同步 |
| `calico-kubeconfig` | 节点 `/etc/cni/net.d/` | CNI 插件访问 API server 的凭据 |

### 3.4 数据面

- 默认 **iptables** 数据面（本项目未启用 BPF 模式）
- 跨节点封装：**IP-in-IP**（`ipipMode: Always`），宿主机隧道设备 `tunl0` 为 `UP`
- 验证：`ip -br link show tunl0` → `tunl0@NONE UNKNOWN 0.0.0.0 <NOARP,UP,LOWER_UP>`

## 四、网络策略（NetworkPolicy）

Calico 原生支持 k8s `NetworkPolicy`（`policy: { type: k8s }`）。示例（拒绝 default 命名空间入站、仅放行业务）：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: default
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-api
  namespace: default
spec:
  podSelector: { matchLabels: { app: api } }
  ingress:
  - from:
    - podSelector: { matchLabels: { app: frontend } }
    ports:
    - { protocol: TCP, port: 8080 }
```

> 若需 L7（HTTP/DNS 感知）策略或 eBPF 数据面，参照 `../eBPF-可观测性/Cilium-生产配置指南.md` 的 Cilium 方案。

## 五、大规模（>50 节点）：Typha

```yaml
# calico.yaml 片段
apiVersion: operator.tigera.io/v1
kind: Installation
spec:
  typha:
    enabled: true
    replicas: 3        # 按规模调整
```

Typha 缓存 API server 状态，felix 改连 Typha，降低 API server 压力。

## 六、跨节点加密（合规）

```yaml
apiVersion: operator.tigera.io/v1
kind: Installation
spec:
  calicoNetwork:
    wireguardEnabled: true   # 或 ipsec
```

## 七、从 Cilium 切换到 Calico（本项目已实操）

> 完整步骤与回退见 `../CNI总览/CNI-生产配置对比.md`；本项目实测步骤如下。

1. 卸载 Cilium：`helm uninstall cilium -n kube-system --wait`
2. 清理残留 taint：`kubectl taint nodes --all node.cilium.io/agent-not-ready:NoSchedule-`
3. 逐节点恢复 Calico CNI 配置：
   ```bash
   rm -f /etc/cni/net.d/05-cilium.conflist
   mv /etc/cni/net.d/10-calico.conflist.cilium_bak /etc/cni/net.d/10-calico.conflist
   ```
4. **重启全部节点**（清除 Cilium 残留的 eBPF 程序，否则会干扰 Calico）：
   ```bash
   # 逐台重启，cordon 避免过渡期误调度；master 须保持 etcd 2/3 quorum
   kubectl cordon <node>; ssh <node> "reboot"; kubectl uncordon <node>
   ```
5. 验证（见第八节）。

### 实测现象与注意

- calico-node 在 Cilium 接管期处于「容器 Running 但 CNI 角色失效」的异常态（重启 30+ 次）；恢复 `10-calico.conflist` 并重启节点后，立刻回到 `1/1 Running` 稳定态。
- 重启过程中 API 会短暂不可达（master 重启瞬间 etcd 抖动），属正常，待节点 `Ready` 后恢复。
- 切换后 Pod IP 由 Cilium 的 `10.0.x.x` 变为 Calico 的 `10.244.x.x`，全家桶（argocd/cert-manager/ES/Prometheus/Tomcat 等）在 Calico 网络上重建并回到 Running/Ready。

## 八、验证结果（2026-07-09 实测）

| 验证项 | 结果 |
|:---|:---|
| calico-node DaemonSet | 5/5 `1/1 Running` |
| Pod IP 段 | `10.244.235.x`（worker1）/ `10.244.189.x`（worker2），即 IPPool `10.244.0.0/16` |
| 宿主机 `tunl0` | `UP`（IP-in-IP 隧道正常） |
| 跨节点路由 | Pod 默认路由经 Calico veth 网关 `169.254.1.1`，跨子网走 `tunl0` |
| 全家桶健康 | argocd / cert-manager / elasticsearch / prometheus / tomcat 等均回到 Running/Ready（分布式组件跨节点通信正常） |

> 注：本环境 `docker.io` 未做镜像代理，busybox 等测试镜像拉取失败，故连通性用「节点 `tunl0` 状态 + 真实业务 Pod 健康度 + 路由核查」综合证明，未用合成 ping。

## 九、生产调优清单

- [ ] IPPool CIDR 与底层网络不冲突，跨子网设 `ipipMode`/`vxlanMode`
- [ ] MTU：`mtu: 0` 自动；隧道场景（IPIP）减 20（如 1440/1442）
- [ ] 大规模启用 Typha（`replicas` 随规模）
- [ ] 合规场景启用 WireGuard/IPsec
- [ ] calico-node 设 resources requests/limits，避免挤占 master
- [ ] `calicoctl` 接入排障（本集群 calicoctl 未单装，可用 `kubectl exec calico-node -- calicoctl ...` 或节点镜像自带）
- [ ] 切换其他 CNI 前，务必重启节点清除旧数据面残留（eBPF/iptables）

## 十、故障排查

见 `故障排查手册.md`（Pod 不通 / 无 IP / 策略失效 / MTU / Typha 等）。
