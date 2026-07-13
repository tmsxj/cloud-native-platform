# P2b.12 — Elasticsearch 3 节点集群（方案 A 的 trace 存储后端）

> 📌 **方案 A 的存储组件**：Elasticsearch 是**方案 A（SkyWalking）**的 trace 存储后端，当前未运行（为省资源已卸载，释放约 6Gi+ worker 内存），但 manifest（`es-cluster.yaml`）仍保留，可随时部署切回方案 A。方案 B 的 traces 改用 **Tempo（链路追踪后端） + MinIO S3**（见 [`../05-otel/README.md`](../05-otel/README.md)）。
> 📅 2026-07-06 完成 | 验证状态: ✅ 3 节点 GREEN | sw_metrics/sw_records 含 replica

## 做了什么

1. 从单节点 `discovery.type: single-node` 改造为 3 节点集群
2. StatefulSet（有状态工作负载） + headless Service + publishNotReadyAddresses
3. 踩坑修复: vm.max_map_count / ES security bootstrap check / DNS 解析

## 集群配置

| 参数 | 值 | 说明 |
|------|-----|------|
| 节点数 | 3 (w1×2, w2×1) | es-0/es-1/es-2 |
| ES 版本 | 8.11.0 | 离线镜像 |
| JVM 堆 | 512MB × 3 | ES_JAVA_OPTS="-Xms512m -Xmx512m" |
| 总内存 | ~2.6GB (实际) | limits: 1Gi × 3 |
| 集群名 | k8s-monitoring | — |
| 发现方式 | seed_hosts + initial_master_nodes | headless DNS |
| xpack.security | false (演示环境) | — |
| PVC | 2Gi × 3, local-path | — |

## 关键设计

```yaml
# StatefulSet 关键配置
podManagementPolicy: Parallel   # 3 节点并行启动
serviceName: elasticsearch-headless  # headless Service, DNS 发现
env:
  - name: node.name
    valueFrom:
      fieldRef:
        fieldPath: metadata.name   # elasticsearch-0, -1, -2
  - name: cluster.initial_master_nodes
    value: "elasticsearch-0,elasticsearch-1,elasticsearch-2"
  - name: discovery.seed_hosts
    value: "elasticsearch-headless.monitoring.svc.cluster.local"
  - name: xpack.security.enabled
    value: "false"                 # 演示环境关闭安全
```

## 踩坑记录

| 问题 | 原因 | 修复 |
|------|------|------|
| `bootstrap check failure: max_map_count too low` | 宿主机 65530 < 262144 | `sysctl -w vm.max_map_count=262144` |
| `security_auto_configuration_exception` | 多节点模式 + xpack.security.enabled=true | 关掉 xpack.security |
| Pod 间 DNS 不通 | headless Service（服务，集群内服务发现） 无 publishNotReadyAddresses | 加 `publishNotReadyAddresses: true` |
| PVC Pending | 缺 storageClassName | 加 `storageClassName: local-path` |

## 验证方式

```bash
# 集群健康
kubectl exec -n monitoring elasticsearch-0 -- curl -s 'http://localhost:9200/_cluster/health'
# {"cluster_name":"k8s-monitoring","status":"green","number_of_nodes":3,...}

# 节点列表
kubectl exec -n monitoring elasticsearch-0 -- curl -s 'http://localhost:9200/_cat/nodes?v'
# 3 nodes with roles: himrst (data, ingest, master, ...)

# 分片分配
kubectl exec -n monitoring elasticsearch-0 -- curl -s 'http://localhost:9200/_cat/allocation?v'
```

## 面试要点

1. **单节点→集群改造**: 核心三步: 删 `discovery.type` → 加 `discovery.seed_hosts` + `initial_master_nodes` → headless Service
2. **ES 节点发现机制**: Zen Discovery → seed_hosts 提供初始节点列表 → 节点间 gossip 协议发现其余节点
3. **分片副本**: 集群模式下自动创建 replica，Green = primary + replica 全部分配
4. **为什么不用 ECK Operator（操作符，自动化运维控制器）**: 演示环境，理解底层手工配置比用 Operator 更能体现深度
5. **JVM 堆建议**: 不超过 50% 物理内存，不超过 32GB（压缩指针上限）
