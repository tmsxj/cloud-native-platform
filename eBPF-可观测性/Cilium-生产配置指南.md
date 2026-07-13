# Cilium（基于 eBPF 的 CNI/网络方案） 生产配置指南

> 创建日期：2026-07-09
> 定位：CNI（容器网络接口） / 网络 / 可观测性 一体化数据面（eBPF 原生）
> 适用：云原生新平台、追求性能与七层可见性、节点内核 ≥5.4 的环境
> 与本项目关系：当前集群已按本指南**完整接管 CNI**（`cni.enabled=true`、`kubeProxyReplacement=false` 保留 kube-proxy），Calico（CNI/网络策略方案） 已下电并备份为 `10-calico.conflist.cilium_bak`；Cilium 1.17.6 运行正常，5 节点 Ready。本指南给出生产级配置与下方实测切换记录。

---

## 一、何时选 Cilium

- 节点内核 ≥5.10（推荐），可启用全部 eBPF（内核可编程技术） 能力
- 想去掉 kube-proxy、去掉 iptables，用 eBPF 做 Service（服务，集群内服务发现） 负载均衡
- 需要七层（HTTP/gRPC/DNS）流量可见性 → Hubble
- 追求高吞吐、低延迟，或大规模集群性能天花板

## 二、生产前置条件

| 项 | 要求 |
|:---|:---|
| 内核 | ≥4.19 基础 eBPF；≥5.4 支持 kubeProxyReplacement；≥5.10 全部特性 |
| 架构 | amd64 / arm64 |
| Helm（K8s 包管理器） | ≥3.8 |
| 冲突 CNI | 安装前**必须移除**其他 CNI 的配置与 DaemonSet（如 Calico） |
| kube-proxy | 可被 Cilium 替换，需确认无外部组件依赖它 |

## 三、核心生产配置（values.yaml）

基于本项目 `cilium-values.yaml` 扩展，关键差异已注释：

```yaml
# —— 数据面 ——
kubeProxyReplacement: true      # 生产推荐 true/strict，彻底去 kube-proxy
routingMode: native             # 直连路由（需底层网络支持 BGP/直连）；否则用 tunnel
tunnel: vxlan                   # routingMode=tunnel 时启用；性能低于 native
bpf:
  masquerade: true

# —— 可观测性 ——
hubble:
  enabled: true
  relay:
    enabled: true
  ui:
    enabled: true               # 生产可关 UI 仅留 relay + Grafana 数据源

# —— 跨节点加密（合规场景开启）——
encryption:
  enabled: false
  type: wireguard               # 或 ipsec

# —— 封装场景 MTU 需减 50 ——
mtu: 1450

# —— 资源（避免挤占 master 内存）——
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    memory: 1Gi

# —— 大规模（>50 节点）——
operator:
  replicas: 2
```

## 四、网络策略（CiliumNetworkPolicy，L7 示例）

比原生 NetworkPolicy 多 L7（HTTP/DNS 感知）能力：

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: api-allow-frontend
  namespace: prod
spec:
  endpointSelector:
    matchLabels: { app: api }
  ingress:
  - fromEndpoints:
    - matchLabels: { app: frontend }
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
      rules:
        http: [ { method: GET, path: /health } ]
```

## 五、生产调优清单

- [ ] `kubeProxyReplacement=true`，`cilium status --verbose` 确认 KubeProxyReplacement 为 true
- [ ] `uname -r` 确认内核 ≥5.10（推荐）
- [ ] MTU 与底层网络一致（VXLAN 1450 / 直连 1500）
- [ ] Hubble relay+UI 启用并接入 Grafana（参考 `import_cilium_dashboard.py`）
- [ ] `cilium-agent` 设 requests/limits，避免 master 内存紧张（见 P2c.10 重分配）
- [ ] 大规模集群调大 BPF map 容量
- [ ] 迁移前备份原 CNI 配置（参考 `backup/calico-cni-before-cilium.conflist`）

## 六、故障排查

| 现象 | 排查命令 / 方向 |
|:---|:---|
| Pod（容器组） 网络不通 | `cilium status`、`cilium connectivity test` |
| Service 不通 | 确认 kubeProxyReplacement 与 kube-proxy 互斥，只留其一 |
| Hubble 无数据 | 查 `hubble-relay` Pod 状态、ServiceMonitor 是否接入 Prometheus（指标监控系统） |
| 内核不支持 | `uname -r`；版本不足则降级 `kubeProxyReplacement=false`（legacy 模式） |

> 部署期踩坑（CrashLoop / taint 死锁 / Grafana（可视化面板） 数据源选错 / Hubble 无数据等）已汇总至 `故障排查手册.md`，按现象快速定位。

## 七、与本项目现状的关系

当前集群 **Cilium 已完整接管 CNI**（`cni.enabled=true`、`kubeProxyReplacement=false` 保留 kube-proxy），Calico 已下电、CNI 配置备份为 `10-calico.conflist.cilium_bak`，CRD（自定义资源定义） 已清理。5 节点全部 Ready，Cilium 1.17.6 运行正常。

> 注：是否保留 Calico 作为运行态备援可自行取舍；作为**资料沉淀**，Calico 配置见 `../Calico-配置指南/`。切换的完整实战与踩坑见下方第八节。

---

## 八、实测：Calico → Cilium 切换实战（2026-07-09）

### 8.1 环境关键事实（先纠正一个记录错误）
- 本集群实际是 **kubeadm** 集群（**不是 K3s**）。kubeconfig 真实路径为 `/etc/kubernetes/admin.conf`（server: `https://192.168.1.51:6443`）；`/etc/rancher/k3s/k3s.yaml` 并不存在。
- kubectl 在 `/usr/bin/kubectl`，需 `sudo`。推荐把命令写脚本 scp 到 m1 再用 `sudo bash /tmp/xxx.sh` 执行（sudo 会重置环境变量，脚本内 `export KUBECONFIG=...` 最稳，避免 kubectl 回退到默认 `localhost:8080`）。
- 节点：m1/m2/m3 = control-plane，w1/w2 = worker；apiserver/etcd 由 kubeadm 静态 Pod 托管。

### 8.2 切换步骤
1. **下电 Calico**：各节点删除 `10-calico.conflist`（备份至 `/root/calico-conflist-backup`），并
   `kubectl delete ds calico-node` / `deploy calico-kube-controllers` / `ippool default-ipv4-ippool`，最后清理 `crd.projectcalico.org` 的 18 个 CRD。
2. **安装 Cilium**（helm，`cni.enabled=true`）：
   ```bash
   helm install cilium /tmp/cilium-1.17.6.tgz \
     -f /tmp/cilium-values.yaml --set cni.enabled=true \
     -n kube-system
   ```
3. **致命坑（本次已踩，务必先固化）**：节点在 CNI 切换期处于 `NotReady`，被 kube-controller-manager 自动打上
   `node.kubernetes.io/not-ready:NoSchedule` 与 `node.kubernetes.io/network-unavailable:NoSchedule` 两个 taint。
   而 Cilium agent DaemonSet（守护进程集） **默认只容忍 `control-plane` / `master` / `agent-not-ready` 三条**，不容忍上面两个
   → agent Pod 始终 `DESIRED=0` → CNI 永远起不来 → 节点永远 NotReady（鸡生蛋死锁）。
   - 现象：`kubectl get ds cilium` 显示 `DESIRED 0`；`kubectl get nodes` 全 `NotReady`；但 apiserver/etcd/coredns 其实健康（`/healthz` 返回 ok）。
   - 根治：在 `cilium-values.yaml` 的 `tolerations` 追加对这两个 taint 的容忍（仓库 `cilium-values.yaml` 已固化）。重装/升级后 DaemonSet 自带完整容忍，agent 先调度把 CNI 拉起，节点随即 Ready、taint 自动消失。
   - 临时救急（重启后会丢，需 `helm upgrade` 固化）：
     ```bash
     kubectl -n kube-system patch ds cilium --type=json \
       -p='[{"op":"add","path":"/spec/template/spec/tolerations/-","value":{"operator":"Exists"}}]'
     ```
4. 固化：`helm upgrade` 到 revision 3，DaemonSet 自带完整 5 条 tolerations，不再依赖手动 patch。

### 8.3 基础验证结果（2026-07-09 实测）
| 项 | 结果 |
|:---|:---|
| 节点状态 | 5/5 Ready |
| cilium agent | 5/5 Running |
| cilium-envoy | 5/5 Running |
| hubble-relay / hubble-ui | Running / 2/2 Running |
| CNI 配置 | m1 `/etc/cni/net.d/05-cilium.conflist` 已生成 |
| 全家桶 | argocd / elasticsearch(3) / skywalking-oap 重启后全部 Running（网络恢复即自愈）|

### 8.4 正式跨节点连通实测（2026-07-09）
在 worker1 / worker2 各起一个 busybox Pod（镜像 `192.168.1.61/docker.io/library/busybox:latest`），做双向连通：

| 测试项 | 源 → 目标 | 结果 |
|:---|:---|:---|
| Pod IP 分配 | nettest-a=`10.0.3.212`(worker1)，nettest-b=`10.0.4.215`(worker2) | 均为 **Cilium IPAM 网段 10.0.x.x** ✓ |
| 跨节点 ICMP | A → B | 4/4 收，**0% 丢包**，avg 0.44ms |
| 跨节点 ICMP | B → A | 4/4 收，**0% 丢包**，avg 0.52ms |
| 跨节点 TCP | A → B:8080 (httpd) | HTTP 握手成功（404 为无 index 的应用层响应，TCP 层已通）|
| 集群 DNS | A → coredns | `kubernetes.default` 解析成功（ClusterIP 10.96.0.1）|

- `ttl=63`（64-1）说明报文经隧道转发一跳，符合 `routingMode: tunnel` + vxlan 的跨节点封装路径。
- 实测证明 Cilium 数据面**跨节点 L3/L4 + DNS 全通**，切换闭环完成。

### 8.5 固化与清理要点
- `tolerations` 必须包含 `not-ready` 与 `network-unavailable` 容忍，否则下次 `helm upgrade` 会再次触发死锁。仓库 `cilium-values.yaml` 已固化。
- 切换 CNI 前确保用对 kubeconfig 路径（本次就因记错 K3s 路径导致 kubectl 全连 localhost:8080，误判为"命令空输出"）。
- 残留清理：Calico 18 个 CRD 已删；各节点 `/etc/cni/net.d/calico-kubeconfig` 为无害残留（Cilium 不读取），可保留亦可清理。
