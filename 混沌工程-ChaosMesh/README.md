# 长期18 — Chaos Mesh 混沌工程

> 📅 完成: 2026-07-09 | 状态: ✅ 已部署（chaos-testing 命名空间，worker 限定）| 验证: PodChaos 实测 `phase=Injected` 且目标 Pod 被删重建成功；NetworkChaos/StressChaos 实验 YAML 已备，待按需运行
> 配套可观测性: `../可观测性/`（Prometheus + Loki + Tempo），注入故障后可在 Grafana 观察 Pod 重启、延迟、CPU 飙升

## 1. 这是什么 / 为什么做

**混沌工程（Chaos Engineering）** 是通过**主动注入故障**来验证系统在异常下的韧性，而非等线上炸了才发现。Chaos Mesh 是 CNCF 毕业级、K8s 原生的混沌工程平台，用 CRD 描述实验。

本项目做它的目的：
- 验证**已部署应用 + 可观测性链路**在故障下的可观测性闭环（注入 → 指标/日志/链路异常 → 告警）
- 面试亮点：能讲清"我不仅搭了监控，还能主动验证监控在故障下真的看得见"
- 补齐 `eBPF/CNI/可观测性` 之后的**韧性验证**一环

## 2. 架构（3 类组件）

```
┌─────────────────────────────────────────────────────────────┐
│  chaos-testing 命名空间                                        │
│                                                               │
│  chaos-controller-manager  (Deployment, 仅 worker1)           │
│     │  监听 Chaos CRD，调度实验                                 │
│     ▼                                                         │
│  chaos-dashboard           (Deployment, 仅 worker1)           │
│     │  Web UI（可选，端口 2333）                                │
│     ▼                                                         │
│  chaos-daemon  (DaemonSet, ★仅 worker1/worker2★)              │
│     │  通过 node 上容器运行时真正注入故障（kill/网络/CPU/IO）   │
└─────────────────────────────────────────────────────────────┘
        │ 实验对象 = 跑在 worker 上的业务 Pod（tomcat-demo 等）
        ▼
   Prometheus 抓取重启次数/CPU；Grafana 可视化；Loki 看重启日志
```

### 为什么 chaos-daemon 只跑 worker？
master 每节点仅 2.5G（占用 77–89%，余量极小），而 chaos-daemon 是 **DaemonSet，默认会落到每个节点**。若放任它上 master，会把 master1 顶到 ~94% 触发 OOM。本项目的目标应用（tomcat/otel-demo）全在 worker，因此给 `worker1/worker2` 打标签 `chaos-inject=true`，用 `nodeSelector` 把 chaos-daemon 限定在这两个节点，master 完全不受影响。

> ⚠️ 踩坑：最初用 `chaosDaemon.affinity.nodeAffinity` 限定，但该 chart 版本会把 affinity 渲染到错误字段（helm 报 `unknown field`），daemon 仍落到全部节点。改用 **nodeSelector + 标签** 可靠生效。详见 `values-worker-scoped.yaml` 注释。

## 3. 部署

```bash
# 在 m1 上（KUBECONFIG=/etc/kubernetes/admin.conf）
bash deploy.sh
```

`deploy.sh` 做了：
1. 加 helm repo（charts.chaos-mesh.org）
2. 建 `chaos-testing` 命名空间
3. `helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh -n chaos-testing -f values-worker-scoped.yaml`

> ⚠️ **镜像来源**：默认从 `ghcr.io/chaos-mesh/*` 拉取。若节点出网受限导致 `ImagePullBackOff`，改用仓库镜像——先在外网同步机（US→H1）把镜像同步进 Harbor，再在 `values-worker-scoped.yaml` 里加 `image.registry: 192.168.1.61:5000/chaos-mesh` 覆盖（见 `../外网资源同步/`）。

## 4. 三类实验（见 `experiments/`）

> ⚠️ **集群出网限制（实测）**：节点能拉取 `ghcr.io`（Chaos Mesh 镜像即从 ghcr 拉取成功），但**拉不动 `docker.io`**（测试用 `nginx:alpine` 报 `ErrImagePull`）。因此实验目标 Pod 的镜像请用 **Harbor 或 ghcr.io** 源，不要直接引用 docker.io 裸镜像。

| 实验 | CRD | 效果 | 观测点 |
|------|-----|------|--------|
| Pod kill | `PodChaos` | 随机删目标 Pod，验证重建与可用性 | Prometheus `kube_pod_status_restart` / Grafana |
| 网络延迟 | `NetworkChaos` | 给目标 Pod 注入 egress 延迟 | Tempo trace 耗时↑ / Grafana 延迟面板 |
| CPU 压力 | `StressChaos` | 占满目标 Pod 的 CPU | Prometheus `container_cpu_usage` 飙升 |

运行示例：
```bash
kubectl apply -f experiments/pod-kill.yaml      # 改 selector 匹配你的目标 Pod
kubectl get podchaos -n <目标ns>                # 查看实验状态
kubectl delete -f experiments/pod-kill.yaml     # 停止实验
```

> 💡 实验务必用 `kubectl delete` 或设 `duration` 收尾，否则故障会持续。

## 5. 与可观测性联动（核心价值）

注入故障后，打开 Grafana：
- **Metrics**：`kube_pod_status_restart_total` 跳变（PodChaos）；`container_cpu_usage_seconds_total` 飙升（StressChaos）
- **Traces**：被延迟的调用在 Tempo 里 span 耗时明显变长（NetworkChaos）
- **Logs**：Loki 里能看到 `Started` / `Killing` 等重启日志

这就形成了**「注入故障 → 三支柱同时异常 → 验证监控有效」**的闭环，是混沌工程落地的标准证明。

## 6. 卸载

```bash
helm -n chaos-testing uninstall chaos-mesh
kubectl delete namespace chaos-testing
```

## 7. 面试要点

- 混沌工程不是"搞破坏"，是**有假设地验证系统韧性**（先定义稳态指标，再注入故障看是否偏离）
- Chaos Mesh 用 **CRD + controller + 节点 daemon** 实现，故障注入对应用**无侵入**（对比传统需改代码）
- 与可观测性结合才是完整闭环；单独跑混沌没意义
- 生产用法：接 ArgoWCD 定时、配合 SLO 燃烧率告警、在**非高峰 + 有撤销手段**时做
