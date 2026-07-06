# P2a.14 — NFS Provisioner 动态存储供给

> 📅 2026-07-05 完成 | 验证状态: ✅ StorageClass `nfs-client` → PVC → Bound | worker1 调度

## 做了什么

1. 基于 bitnami/kubectl 镜像搭建自定义 NFS Provisioner
2. 监听集群中 `storageClassName=nfs-client` 的 Pending PVC
3. 自动创建 NFS 目录 + PV + Binding
4. 调度到 worker1（NFS 挂载点在该节点）

## 架构

```
PVC (nfs-client) ──Pending──► Provisioner (watch loop, 30s)
                                    │
                                    ▼ mkdir + kubectl create pv
                              PV (NFS, h1:/srv/nfs-k8s/<ns>-<name>)
                                    │
                                    ▼
                              PVC Bound ← NFS ReadWriteMany
```

## 核心组件

| 组件 | 位置 | 说明 |
|------|------|------|
| Deployment | kube-system/nfs-provisioner | 单副本，worker1 |
| ServiceAccount | nfs-provisioner | 需 PV/PVC CRUD 权限 |
| ClusterRole | nfs-provisioner-runner | RBAC |
| StorageClass | nfs-client | immediate binding |
| NFS 服务端 | h1:/srv/nfs-k8s | Harbor 物理机 |

## 已使用 PVC

| PVC | 命名空间 | 大小 | 用途 |
|-----|----------|------|------|
| grafana-nfs | monitoring | 5Gi | Grafana 持久化 |
| prometheus-nfs | monitoring | 30Gi | Prometheus TSDB |
| tomcat-logs-pvc | tomcat-dev | 5Gi | Tomcat 日志 |

## 面试要点

1. **NFS Provisioner 原理**: 不是 K8s 内置 provisioner，是 external provisioner 模式 — watch loop + kubectl create PV
2. **StorageClass 关键字段**: `provisioner` 匹配、`volumeBindingMode: Immediate`、`reclaimPolicy`
3. **NFS 协议**: v4.1、`hard` mount、`timeo=600`（防止网络抖动丢 IO）
4. **与 local-path 对比**: local-path 不支持跨节点共享（RWO），NFS 支持 RWX
5. **生产替代方案**: Longhorn / Ceph RBD / CSI-NFS-Driver
