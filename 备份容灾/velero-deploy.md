# 第 21 项 备份容灾（Velero + 现有 MinIO S3）

> 目标：补齐生产刚需的集群/数据备份恢复能力（DR）。复用集群已有的 MinIO 作为 S3 后端，不另起存储。
> 完成时间：2026-07-09 | 状态：✅ 已完成并验证（备份+恢复闭环）

---

## 一、架构

```
velero (deploy + node-agent DS, ns=velero)
   │ 备份对象 → S3 API
   ▼
MinIO (monitoring 命名空间, 既有)  →  bucket: velero
   S3 端点: http://minio.monitoring.svc:9000
   凭据: minioadmin / minioadmin
```

- Velero 版本：v1.14.1（镜像已同步 Harbor（私有镜像仓库）：`192.168.1.61/velero/velero:v1.14.1`）
- AWS 插件：`192.168.1.61/velero/velero-plugin-for-aws:v1.11.0`
- 镜像获取统一走 `外网资源同步/sync_from_us.ps1`（US→H1→Harbor），集群从 Harbor 自动拉取

## 二、前置：复用现有 MinIO

聚焦模式下 MinIO 被冻结（replicas=0），先拉回：

```bash
kubectl -n monitoring scale deploy minio --replicas=1
kubectl -n monitoring rollout status deploy/minio
```

创建 bucket（一次性 `mc` Pod（容器组），镜像 `192.168.1.61/minio/mc:latest`）：

```bash
kubectl -n monitoring run mc-velero-create --image=192.168.1.61/minio/mc:latest --restart=Never \
  --command -- /bin/sh -c "mc alias set m http://minio.monitoring.svc:9000 minioadmin minioadmin && mc mb --ignore-existing m/velero"
kubectl -n monitoring logs mc-velero-create
kubectl -n monitoring delete pod mc-velero-create
```

## 三、安装（velero CLI，运行于 m1）

> m1 上 `velero` 二进制路径 `/usr/local/bin/velero`（从 GitHub release 下载后 scp 安装）。
> 注意 v1.14 仍需显式 `--plugins`，且 TLS 跳过要放进 `--backup-location-config` 的 `insecureSkipTLSVerify=true`。

```bash
# 凭据文件 /tmp/velero-credentials
[default]
aws_access_key_id=minioadmin
aws_secret_access_key=minioadmin

velero install \
  --provider aws \
  --image 192.168.1.61/velero/velero:v1.14.1 \
  --plugins 192.168.1.61/velero/velero-plugin-for-aws:v1.11.0 \
  --namespace velero \
  --bucket velero \
  --secret-file /tmp/velero-credentials \
  --backup-location-config region=minio,s3ForcePathStyle=true,s3Url=http://minio.monitoring.svc:9000,insecureSkipTLSVerify=true \
  --use-volume-snapshots=false
```

验证：`velero backup-location get` → `default  aws  velero  Available  ReadWrite  true`

## 四、DR 验证（备份 + 恢复闭环）

```bash
# 1) 备份 reliability-demo 命名空间
velero backup create bk-reliability --include-namespaces reliability-demo --wait
velero backup get      # STATUS=Completed, ERRORS=0

# 2) 恢复到新命名空间（不破坏原命名空间，证明可恢复）
velero restore create r1 --from-backup bk-reliability \
  --namespace-mappings reliability-demo:reliability-demo-restored --wait
velero restore get     # STATUS=Completed, ERRORS=0
kubectl get pods -n reliability-demo-restored   # 3 个 demo-app 重建并 Running

# 3) 清理临时恢复命名空间（备份保留在 MinIO 作证据）
kubectl delete namespace reliability-demo-restored
```

结论：备份可读写 MinIO、恢复可重建工作负载，**集群炸了有得恢复**这一生产必答题已闭环。

## 五、资源占用

- velero deployment：1 副本，~100Mi，落在 worker
- node-agent DaemonSet（守护进程集）：仅 worker 节点运行（master 有 NoSchedule 污点，自动不调度，符合预期）
- 对聚焦模式内存预算几乎无影响（验证时 worker1 39% / worker2 53%）

## 六、常用命令速查

```bash
velero backup create <名> --include-namespaces <ns> [--wait]
velero backup get
velero restore create <名> --from-backup <备份名> [--namespace-mappings a:b] [--wait]
velero restore get
velero backup delete <名>        # 同时删 MinIO 中对象
```

## 备份方案对比

| 维度 | Velero（本项目采用） | etcd 快照（snapshot） | 存储卷快照（CSI） |
|------|---------------------|----------------------|------------------|
| 粒度 | 命名空间/资源级，可筛选 | 全集群 etcd | 单 PV（持久卷） |
| 跨集群恢复 | ✅（`--namespace-mappings` 改名恢复） | 仅同构集群恢复 | 需同 CSI 驱动 |
| 后端 | 对象存储（S3/MinIO） | 本地文件 | 块存储快照 |
| 应用感知 | ✅ 可 hook 停写/静默 | ❌ 崩溃一致性 | 依赖 CSI 快照一致性 |
| 适用 | K8s 资源 + 数据整体备份 | 紧急全量回滚 | 有状态单卷快速回滚 |

> 本项目用 Velero + 现有 MinIO（`bucket=velero`）：不另起存储，资源级备份可跨命名空间恢复，补齐 DR 必答题。
