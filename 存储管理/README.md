# P2a.14 — NFS 动态供给器（Provisioner）动态存储供给

> 📅 2026-07-05 完成 | 验证状态: ✅ StorageClass（存储类，`nfs-client`）→ PVC（持久卷声明，PersistentVolumeClaim）→ Bound（绑定） | worker1 调度
> **术语对照**（全文英文术语以 `全局参考/术语表.md` 为准）：StorageClass=存储类；Provisioner=动态供给器；PV=持久卷（PersistentVolume）；PVC=持久卷声明；RBAC（基于角色的访问控制）=基于角色的访问控制（Role-Based Access Control）；RWX=读写多节点（ReadWriteMany）。

## 做了什么

1. 基于 bitnami/kubectl 镜像搭建自定义 NFS 动态供给器（Provisioner）：它是一个**外部供给器（external provisioner）**模式的控制器，不在 K8s（Kubernetes，容器编排引擎） 内置供给之列
2. 监听集群中 `storageClassName=nfs-client` 的 Pending（待绑定）PVC
3. 自动创建 NFS 目录 + PV（持久卷）+ Binding（绑定），让用户无需手动建 PV
4. 调度到 worker1（NFS 挂载点在该节点），因为 NFS 服务端在 h1（192.168.1.61）本地目录，需经 worker 节点挂载

## 动态供给 vs 静态供给（本项目两种都用了）

| 维度 | 静态 PV/PVC（`K8s基础/K8s-三基石` 演示） | 动态供给（本文件，NFS Provisioner） |
|------|----------------------------------------|--------------------------------------|
| PV 由谁创建 | 管理员手动 `kubectl apply` PV | Provisioner 自动创建 |
| 适用场景 | 单应用、固定容量、演示全链路 | 多团队、按需申请、免运维建 PV |
| 绑定方式 | PVC 用 `volumeName` 指名绑定 | StorageClass 按 `storageClassName` 自动匹配 |
| 本项目实例 | tomcat 日志（手动 PV） | Grafana/Prometheus（指标监控系统）/tomcat 日志（自动 PV） |
| 回收策略 | PV 写 `Retain`（删 PVC 留数据） | StorageClass 默认 `Delete`（删 PVC 清数据） |

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
| Deployment（部署） | kube-system/nfs-provisioner | 单副本，worker1 |
| ServiceAccount（服务账号） | nfs-provisioner | 需 PV/PVC 增删改查权限 |
| ClusterRole（集群角色） | nfs-provisioner-runner | RBAC（基于角色的访问控制）授权 |
| StorageClass（存储类） | nfs-client | `volumeBindingMode: Immediate` 立即绑定 |
| NFS 服务端 | h1:/srv/nfs-k8s | Harbor（私有镜像仓库） 物理机，共享根目录 |

## 已使用 PVC

| PVC | 命名空间 | 大小 | 用途 |
|-----|----------|------|------|
| grafana-nfs | monitoring | 5Gi | Grafana（可视化面板） 持久化 |
| prometheus-nfs | monitoring | 30Gi | Prometheus TSDB |
| tomcat-logs-pvc | tomcat-dev | 5Gi | Tomcat 日志 |

## 面试要点

1. **NFS Provisioner 原理**: 不是 K8s 内置 provisioner，是 external provisioner 模式 — watch loop + kubectl create PV
2. **StorageClass 关键字段**: `provisioner` 匹配、`volumeBindingMode: Immediate`、`reclaimPolicy`
3. **NFS 协议**: v4.1、`hard` mount、`timeo=600`（防止网络抖动丢 IO）
4. **与 local-path 对比**: local-path 不支持跨节点共享（RWO），NFS 支持 RWX
5. **生产替代方案**: Longhorn / Ceph RBD / CSI-NFS-Driver
