# eBPF 可观测性 — Cilium 部署实验

> 创建日期：2026-07-07
> 目标：在现有 K3s + Calico 集群上部署 Cilium，验证 eBPF 可观测性能力
> 状态：**Cilium Agent 部署成功，eBPF 程序已加载**

---

## 目录导航

| 文件 | 内容 |
|:---|:---|
| `Cilium-生产配置指南.md` | 生产级完整接管配置（路由/IPAM/BPF/策略/Hubble/加密/资源） |
| `故障排查手册.md` | 8 类踩坑快速定位（CrashLoop / taint 死锁 / 数据源选错 / Hubble 无数据…） |
| `cilium-values.yaml` | 实际部署值（已接管 CNI，kube-proxy 保留） |
| `hubble-servicemonitor.yaml` | Hubble 指标抓取（9965，带 `prometheus: managed`） |
| `cilium-dashboard.json` | Grafana 面板（35 面板含 Hubble 行） |
| `import_cilium_dashboard.py` / `create_grafana_datasource.py` | 面板导入 / 数据源创建 |
| `backup/` | Calico 回退依据（非活跃配置） |

## 架构总览

```
Pod ──> Cilium CNI (05-cilium.conflist) ──> eBPF 数据面 (VXLAN 隧道)
        ├─> Hubble gRPC server (:4244) ──> Hubble Relay ──> Hubble UI / Grafana
        ├─> cilium-agent metrics (:9962) ──┐
        └─> hubble-metrics (:9965) ─────────┤──> managed Prometheus ──> Grafana Dashboard
        kube-proxy 保留：Service NAT 仍由 kube-proxy 负责（kubeProxyReplacement=false）
        Calico 已停用：10-calico.conflist.cilium_bak（回退备份，见 backup/）
```

## 生产决策速查

| 场景 | 本项目配置 |
|:---|:---|
| 兼容已有 CNI / K3s | `routingMode: tunnel` + `tunnelProtocol: vxlan` |
| 低资源 master | Agent requests 256Mi / limits 512Mi，容忍 control-plane |
| 七层可观测 | `hubble.enabled=true` + `listenAddress: ":4244"` + Relay + UI |
| 监控管线接入 | `prometheus.enabled` + ServiceMonitor 带 `prometheus: managed` |
| 避免 taint 死锁 | `agentNotReadyTaintKey: ""` + tolerations 含 `node.cilium.io/agent-not-ready` |

## 与 Calico 的关系

- 同集群同刻只能有一个 CNI 真正接管 Pod 网络（kubelet 按 CNI 配置文件名字典序加载）。
- 本项目现状：**Cilium 已实际接管**，Calico 仅作回退备份；上层全家桶不依赖特定 CNI。
- 选型对比见 `../CNI总览/CNI-生产配置对比.md`；Calico 资料见 `../Calico-配置指南/`。

---

## 一、集群前置条件

| 检查项 | 结果 | 说明 |
|:---|:---|:---|
| 内核版本 | 5.15.0-185-generic | ✅ 支持 eBPF（4.10+） |
| CNI | Calico v3.26.0 | 当前网络插件 |
| kube-proxy | DaemonSet（iptables模式） | K3s 自带 |
| K8s 版本 | v1.28.15 (K3s) | ✅ Cilium 1.17 支持 |
| Pod CIDR | 10.244.0.0/16 | Calico IP-in-IP |
| 节点 | 3 master (2C/2G) + 2 worker (8C/8G) | worker 有充足资源 |
| Helm | v3.21.2 | 本次安装 |

---

## 二、部署策略

**核心原则：不替换 Calico CNI，不替换 kube-proxy，Cilium 仅做 eBPF 可观测**

- `cni.enabled=false` — 不接管 CNI，保留 Calico
- `kubeProxyReplacement=false` — 不替换 kube-proxy
- `routingMode=tunnel` — VXLAN 隧道模式（兼容 Calico）
- `agentNotReadyTaintKey=""` — 禁用 agent-not-ready taint（避免循环阻塞）

---

## 三、部署过程

### Step 1：安装 Helm（master1）

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version  # v3.21.2
```

### Step 2：下载 Cilium Chart

```bash
curl -fsSL https://helm.cilium.io/cilium-1.17.6.tgz -o /tmp/cilium-1.17.6.tgz
```

### Step 3：创建 values 配置

见同目录 `cilium-values.yaml`

### Step 4：部署

```bash
helm install cilium /tmp/cilium-1.17.6.tgz -f cilium-values.yaml --namespace kube-system --wait --timeout 300s
```

### Step 5：验证

```bash
# Agent 状态
kubectl exec -n kube-system cilium-<pod> -- cilium status

# eBPF 程序验证
kubectl exec -n kube-system cilium-<pod> -- cilium bpf lb list
kubectl exec -n kube-system cilium-<pod> -- cilium bpf ct list global

# DaemonSet 状态
kubectl get ds cilium -n kube-system
```

---

## 四、踩坑记录（重要！）

### 坑 1：routingMode=native 需要 ipv4NativeRoutingCIDR

**现象**：Agent CrashLoop，日志 `fatal msg="invalid daemon configuration: native routing cidr must be configured"`

**原因**：`routingMode: native` 需要节点之间能直接路由 Pod CIDR，K3s + Calico 环境不满足

**解决**：改用 `routingMode: tunnel`（VXLAN 隧道模式）

### 坑 2：autoDirectNodeRoutes 与 tunnel 冲突

**现象**：Agent CrashLoop，日志 `fatal msg="auto-direct-node-routes cannot be used with tunneling"`

**原因**：tunnel 模式下不能同时启用 autoDirectNodeRoutes

**解决**：删除 `autoDirectNodeRoutes: true`

### 坑 3：agent-not-ready taint 导致 Pod 调度阻塞

**现象**：所有节点被打上 `node.cilium.io/agent-not-ready:NoSchedule` taint，CoreDNS 被 Pending

**原因**：Cilium Agent 启动/重启过程中会给节点打 taint；如果 Agent CrashLoop，taint 永不被清除

**解决**：
1. 卸载 Cilium：`helm uninstall cilium -n kube-system`
2. 手动清除 taint：`kubectl taint nodes <node> node.cilium.io/agent-not-ready:NoSchedule-`
3. 配置中加 `agentNotReadyTaintKey: ""` 禁用此功能

### 坑 4：Hubble Relay 无法连接 Agent Hubble Server

**现象**：Hubble Relay 一直重启，日志 `dial tcp 10.111.102.5:443: connect: connection refused`

**原因**：`cni.enabled=false` 模式下，Cilium Agent 默认不启动 Hubble gRPC server（端口 4244）

**结论（已修正 ✅）**：该问题在 Revision 4 中通过显式设置 `hubble.listenAddress: ":4244"` 已解决。实测 Hubble 正常工作——`cilium hubble status` 显示 `Hubble: Ok`，当前/最大流 1883/4095 (45.98%)、3.47 flows/s，Hubble Relay 与 Hubble UI 均 Running。**CNI disabled 模式下 Hubble 可观测性可用**。

### 坑 5：SSH Key 认证失效

**现象**：`ssh root@192.168.1.51` 报 `Permission denied (publickey,password)`

**原因**：集群重启后 SSH authorized_keys 可能被重置，或 Windows SSH agent 未加载 key

**解决**：安装 paramiko，通过 Python 脚本密码认证连接

### 坑 6：helm upgrade 滚动更新时 `agent-not-ready` taint 死锁（Revision 5 实战踩坑）

**现象**：执行 `helm upgrade` 接入 Prometheus 后，Cilium DaemonSet 滚动更新，部分节点上的新 Pod 长时间 `Pending`。`kubectl describe pod` 报：
`0/5 nodes are available: 1 node(s) had untolerated taint {node.cilium.io/agent-not-ready: }. ... 4 node(s) didn't match Pod's node affinity/selector.`

**原因**：滚动更新删除旧 Cilium Pod 时，节点残留了 `node.cilium.io/agent-not-ready:NoSchedule` taint（Cilium Agent 启动早期会打该 taint，ready 后移除）。而新 Pod 的 `tolerations` 里**没有**该 taint 的容忍项，且 Pod 因 taint 无法调度 → Agent 永远不 ready → taint 永不移除，形成死锁。实测 `agentNotReadyTaintKey: ""` 在 Cilium 1.17 确实生效（helm values 确认、Agent ready 后节点 taint 干净），但滚动更新窗口内仍可能短暂残留。

**解决**：
1. 清除所有节点的该 taint，让 Pod 能调度：
   ```bash
   kubectl taint nodes --all node.cilium.io/agent-not-ready:NoSchedule-
   ```
2. 若个别节点 Pod 仍 Pending，删除该 Pod 触发 DaemonSet 立即重建：
   ```bash
   kubectl delete pod <cilium-pod> -n kube-system
   ```
3. 验证全量就绪：`kubectl get ds cilium -n kube-system` 应显示 `DESIRED=READY=5`，所有节点 taint 仅剩 `control-plane`。

**根治方案**：在 `cilium-values.yaml` 的 `tolerations` 中追加 `node.cilium.io/agent-not-ready:NoSchedule` 容忍项，使 Pod 即使遇残留 taint 也能调度，彻底避免死锁。

### 坑 7：Grafana 默认 Prometheus 数据源没有 Cilium 数据（必须建专用数据源）

**现象**：dashboard 导入后所有面板为空，经 Grafana 数据源代理查询 `count(up{job="cilium-agent"})` 返回空。

**原因**：集群里有两个 Prometheus 实例，Grafana 默认数据源指向了「错的那个」：
- `prometheus-server`（kube-prometheus 社区版，Grafana 默认数据源 id=1，url `prometheus-server.monitoring:80`）——其 `serviceMonitorSelector` 不匹配 `prometheus: managed` 标签，**不抓取 Cilium**。
- `prometheus-managed-0`（为 Cilium 建的 `managed` Prometheus CR，Service `prometheus-operated.monitoring:9090`）——Cilium ServiceMonitor 的 `prometheus: managed` 标签精确命中它，**Cilium 数据全在这里**。

**解决**：在 Grafana 新建专用数据源指向 managed Prometheus，并让 dashboard 绑定它：
- 名称 `Prometheus-Cilium`，uid `afrhyqopp15ogc`，类型 `prometheus`，url `http://prometheus-operated.monitoring:9090`，access `proxy`
- dashboard 全部 22 个面板 / templating 均绑定该 uid（而非默认 `PBFA97CFB590B2093`）

**验证结果**：经该数据源代理 `count(up{job="cilium-agent"})=5`；dashboard 所用 18 个指标 `HAVE_DATA=18/18`，全部有数据；dashboard URL `/d/cilium-ebpf-mon/cilium-ebpf-agent-monitoring` 正常可用。

**补充（`cilium-values.yaml` 配置提醒）**：`prometheus.metrics` 中的 `+cilium_datapath_drop_count_total`、`+cilium_endpoint_count`、`+cilium_policy_endpoint_enforcement`、`+cilium_dns_queries_total`、`+cilium_dns_records_count`、`+cilium_events_drop` 这些名称在 agent 中**并不存在**（被 Cilium 静默忽略）。真实暴露名是 `cilium_drop_count_total` / `cilium_endpoint` / `cilium_endpoint_state` / `cilium_policy_endpoint_enforcement_status` 等——agent **默认即暴露**，无需 `+` 启用。本 dashboard 即基于这些真实暴露指标构建，与 `prometheus.metrics` 中的 `+` 列表无依赖。

### 坑 8：Hubble 流量/DNS 可观测性默认没接入 Prometheus（需单独的 ServiceMonitor）

**现象**：Hubble 组件（relay/UI/metrics service）都部署了，但 Grafana 里看不到任何 flow/drop/DNS 面板——因为 `hubble-metrics:9965` 端点虽然在，却**没有对应的 ServiceMonitor**，指标根本没进 Prometheus。

**原因**：Cilium helm chart 只为我们配了 `cilium-agent` 的 ServiceMonitor（agent 级 eBPF 指标，9962），**没有**为 `hubble-metrics`（9965）建 ServiceMonitor。Hubble 的 flow/drop/tcp/lost 指标因此一直停留在 Hubble UI，没进入监控管线。

**解决**：新增 `hubble-servicemonitor.yaml`，同样带 `prometheus: managed` 标签，selector 匹配 `hubble-metrics` Service 的 `k8s-app: hubble`，抓取 9965。apply 后 `managed` Prometheus 立即出现 `serviceMonitor/kube-system/hubble-metrics/0` 作业。

**验证结果**：`hubble_flows_processed_total`=44 series、`hubble_drop_total`=5、`hubble_tcp_flags_total`=20、`hubble_lost_events_total`=15；dashboard 新增「Hubble 网络可观测性」行（6 图）均有数据。

**注意（DNS 指标）**：`hubble_dns_queries_total` 当前为 **0 series**。原因是 `hubble.metrics.enabled` 曾误写为 `dns:query`（无效），已改为规范 `dns`，但 `hubble_dns_queries_total` 仍需**实际 DNS 流量**经过被观测路径才会产生 series。安静的 lab 环境下该面板为空属正常，跑点 DNS 查询后即会出数。

---

## 五、最终部署状态

### 组件状态

| 组件 | 状态 | 说明 |
|:---|:---|:---|
| Cilium Agent (DaemonSet) | 5/5 Running | 每节点一个，1/1 Ready |
| Cilium Envoy | 5/5 Running | 外部 Envoy proxy |
| Cilium Operator | 1/1 Running | Deployment |
| Hubble UI | 2/2 Running | Web 界面 |
| Hubble Relay | Running | 通过 listenAddress: :4244 启用 Hubble gRPC server，已稳定 24h+ |
| Cilium Metrics (cilium-agent) | ClusterIP :9962 | eBPF/Hubble 指标端点，供 Prometheus 抓取 |
| Hubble Metrics (hubble-metrics) | ClusterIP :9965 | dns/drop/tcp/flow 指标端点 |
| Prometheus 纳管 | ✅ 10 targets | 2 个 ServiceMonitor（`cilium-agent`×5 + `hubble-metrics`×5），均带 `prometheus: managed` 标签，被 `managed` 实例抓取 |
| Hubble 指标接入 | ✅ 可用 | `hubble-servicemonitor.yaml` 创建 ServiceMonitor 抓取 `hubble-metrics:9965`；flows/drop/tcp/lost 4 类指标已入 Prometheus |
| Grafana Dashboard (Cilium) | ✅ 可用 | uid `cilium-ebpf-mon`，35 面板（含 Hubble 行 + 6 图）绑定 `Prometheus-Cilium` 数据源(uid `afrhyqopp15ogc`)；agent 18/18 + hubble 4/5 指标有数据 |

### Cilium Agent 关键指标

- **Cluster health**: 5/5 reachable
- **Controller Status**: 32/32 healthy
- **Proxy Status**: OK, Envoy external
- **IPAM**: 4/254 allocated from 10.0.4.0/24
- **Routing**: Network: Tunnel [vxlan] | Host: Legacy
- **Attach Mode**: Legacy TC

### 资源消耗

| 组件 | CPU (每节点) | 内存 (每节点) |
|:---|:---|:---|
| Cilium Agent | 17-30m | 119-124Mi |
| Cilium Envoy | 3-5m | 12-13Mi |
| **合计** | ~25m | ~140Mi |

### 节点资源影响

| 节点 | CPU | 内存（部署后） | 内存（部署前） |
|:---|:---|:---|:---|
| master1-3 | 12-16% | 95-97% (1.75-1.78G) | 83-88% (1.52-1.61G) |
| worker1-2 | 2% | 39-50% (3.0-4.0G) | 30-36% (2.4-2.9G) |

> Master 内存增加约 200-250Mi（来自 Cilium Agent + Envoy + Hubble UI），Master 已接近满载

---

## 六、eBPF 能力验证

### BPF Service Load Balancer ✅

```bash
kubectl exec -n kube-system cilium-<pod> -- cilium bpf lb list
# 输出：SERVICE ADDRESS → BACKEND ADDRESS 映射
# 10.96.43.146:443/TCP → 10.244.235.139:10250/TCP
```

### BPF Connection Tracking ✅

```bash
kubectl exec -n kube-system cilium-<pod> -- cilium bpf ct list global
# 输出：活跃 TCP 连接，含标志位、过期时间、包计数
```

### Cilium Endpoint ✅

```bash
kubectl get ciliumendpoints -A  # 列出所有被 Cilium 管理的 Endpoint
```

---

## 七、清理（如需回滚）

```bash
# 1. 卸载 Cilium
helm uninstall cilium -n kube-system --wait

# 2. 清理残留 taint
kubectl taint nodes node.cilium.io/agent-not-ready:NoSchedule- --all

# 3. 清理 CRDs（可选）
kubectl get crds | grep cilium.io | awk '{print $1}' | xargs kubectl delete crd
```

> **完整回退到 Calico（可选）**：上面只卸载了 Cilium，但节点上 Cilium 已实际接管 CNI
> （`/etc/cni/net.d/05-cilium.conflist` 生效，Calico 配置被备份为 `10-calico.conflist.cilium_bak`）。
> 若要把网络交还给 Calico，需在每个节点执行：
> ```bash
> sudo mv /etc/cni/net.d/10-calico.conflist.cilium_bak /etc/cni/net.d/10-calico.conflist
> sudo rm -f /etc/cni/net.d/05-cilium.conflist
> sudo systemctl restart containerd kubelet   # 使新 CNI 生效
> ```
> 本仓库已归档接管前的 Calico 配置：`backup/calico-cni-before-cilium.conflist`。

---

## 八、后续方向

1. **Tetragon**：Cilium 生态的 eBPF 可观测性工具，不涉及网络，更适合纯监控场景
2. **Cilium CNI Chaining**：`cni.chainingMode=generic-veth`，附加到 Calico 上，可启用 Hubble
3. **Prometheus 集成（已完成 ✅）**：Revision 5 已开启 `prometheus.enabled` + `prometheus.serviceMonitor.enabled`，并给 ServiceMonitor 打 `prometheus: managed` 标签以匹配 Prometheus Operator 实例（其 `serviceMonitorSelector` 要求该标签）。Cilium eBPF（agent 9962）与 **Hubble 流量指标（hubble-metrics 9965，见坑 8）** 均已进入 `managed` Prometheus 实例（共 10 targets）。
4. **Grafana Cilium Dashboard（已完成 ✅）**：自建 `Cilium eBPF Agent Monitoring` dashboard（uid `cilium-ebpf-mon`，35 面板含「Hubble 网络可观测性」行），基于 agent 与 Hubble 真实暴露指标，绑定专用数据源 `Prometheus-Cilium`（uid `afrhyqopp15ogc` → `prometheus-operated.monitoring:9090`）。注意 Grafana 默认数据源 `prometheus-server` 不抓 Cilium（见坑 7）。

---

## 九、架构现状与目录定位

### 当前真实架构（以节点 `/etc/cni/net.d` 为准，非以 values 注释为准）
- **Cilium 已是实际 CNI**：`05-cilium.conflist`（仅 `cilium-cni`）生效，负责 Pod 网络（VXLAN 隧道模式）。
- **Calico 已被接管**：原 `10-calico.conflist` 被 Cilium 安装器备份为 `10-calico.conflist.cilium_bak`（停用态）。calico-node Pod 虽可能仍 Running，但其 CNI 角色已失效。
- **kube-proxy 保留**：`kubeProxyReplacement: false`，Service 的 NAT 转发仍由 kube-proxy 负责。
- ⚠️ **values 与节点状态不一致说明**：`cilium-values.yaml` 中 `cni.enabled: false` 表示 chart 不管理 CNI 配置；节点上的 Cilium CNI 配置来自更早的部署状态。重新 `helm upgrade` 不会删除已存在的 `05-cilium.conflist`，因此"Cilium 接管 CNI"这一现状会保持。不要被早期"仅监控模式 / 不替换 Calico"的注释误导（已修正）。

### 目录定位
本目录主题虽叫「eBPF 可观测性」，但实际落地的是 **一整套 Cilium 部署**（CNI + Hubble + Prometheus + Grafana）。
- 它应被理解为 **Cilium 网络插件主目录**，而非 Calico/Cilium 并列的目录。
- Calico 仅以**回退备份**形式存在：`backup/calico-cni-before-cilium.conflist`（接管前的原始配置），用于需要时还原，不是活跃部署文件。
- 文件清单：
  | 文件 | 角色 |
  |---|---|
  | `cilium-values.yaml` | Cilium 部署值（实际已接管 CNI） |
  | `hubble-servicemonitor.yaml` | Hubble 指标抓取 |
  | `cilium-dashboard.json` | Grafana 面板（35 面板） |
  | `import_cilium_dashboard.py` / `create_grafana_datasource.py` | 面板导入 / 数据源创建 |
  | `backup/` | 回退依据（非活跃配置，见上） |
