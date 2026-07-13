# P2a.11 — KEDA（基于事件的自动伸缩，Kubernetes（K8s，容器编排引擎） Event-Driven Autoscaling）事件驱动自动伸缩

> 📅 2026-07-05 完成 | 验证状态: ✅ 3 Pod Running + Cron ScaledObject（伸缩对象，CRD（自定义资源定义） 自定义资源）Ready + 底层 HPA（水平 Pod 伸缩，Horizontal Pod Autoscaler）自动生成
> **术语对照**（以 `全局参考/术语表.md` 为准）：KEDA=基于事件的自动伸缩；ScaledObject=伸缩对象（KEDA 的 CRD，声明"用什么触发器、扩到多少副本"）；HPA=水平 Pod 伸缩；CronJob=定时任务（K8s 原生）；metrics-server（指标聚合服务）=指标聚合服务。

## 做了什么

1. 离线部署 KEDA 2.16.1（3 镜像: us→h1→Harbor（私有镜像仓库）→containerd，统一走 `外网资源同步/sync_from_us.ps1`）
2. 部署 Cron ScaledObject（定时伸缩对象）演示 — 工作日 9-18 自动扩缩
3. KEDA（基于事件的自动伸缩） 自动生成底层 HPA（水平 Pod 伸缩），无缝对接 metrics-server（指标聚合服务）

## HPA（水平 Pod 伸缩） vs KEDA（为什么需要 KEDA）

| 维度 | HPA（K8s 原生） | KEDA（事件驱动） |
|------|----------------|------------------|
| 数据来源 | 仅 CPU/内存（或需额外 Adapter 接 Prometheus（指标监控系统）） | 50+ 外部触发器（Cron、Kafka、Redis 队列深度、Prometheus 指标等） |
| 触发模型 | 指标驱动（阈值） | 事件/消息驱动（队列有积压就扩） |
| 与 HPA 关系 | 自身是伸缩执行者 | 在底层**自动创建并管理**一个 HPA，复用其执行链路 |
| 典型场景 | Web 服务 CPU 高就扩 | 消息队列积压、定时工作时段、Prometheus QPS 阈值 |
| 本项目实例 | `K8s基础/K8s（Kubernetes，容器编排引擎）-三基石` 的 tomcat CPU 伸缩 | 本文件 Cron 定时 9-18 扩到 3 副本 |

## 部署架构

```
KEDA Controller ──管理──► ScaledObject (CR)
                              │
                              ▼ triggers: [cron]
                    KEDA Metrics Server
                              │
                              ▼
                    底层 HPA (自动创建)
                              │
                              ▼
                    Deployment (keda-cron-demo)
```

## Cron ScaledObject

| 参数 | 值 | 说明 |
|------|-----|------|
| 触发器类型 | cron | 基于时间 |
| 扩容时段 | 工作日 9:00-18:00 | 上海时区 |
| 目标副本 | 3 (工作时段) / 1 (非工作时段) | — |
| minReplicas | 1 | 下限 |
| maxReplicas | 5 | 上限 |

## 验证方式

```bash
# 检查 KEDA Pods
kubectl get pods -n keda

# 查看 ScaledObject 状态
kubectl get scaledobject keda-cron-scaler -n default

# 查看自动生成的 HPA
kubectl get hpa -n default
# NAME                       REFERENCE                  TARGETS
# keda-hpa-keda-cron-scaler  Deployment/keda-cron-demo  1/1

# 模拟超工作时段（Cron 触发 1 replica）
# KEDA 日志: kubectl logs -n keda -l app=keda-operator
```

## 面试要点

1. **HPA vs KEDA**: HPA 依赖 metrics-server 的 CPU/Mem → KEDA 支持 50+ 外部触发器
2. **CRON 触发器原理**: KEDA 内置 cron 解析器 → 到时间修改 HPA minReplicas → metrics-server 不做任何事
3. **ScaledObject → HPA**: KEDA controller watch ScaledObject → 创建/更新/删除底层 HPA
4. **与传统 CronJob 区别**: CronJob 是 Job 执行，KEDA Cron Scaler 是调整 Deployment（部署，无状态工作负载） 副本数
5. **生产场景**: 工作日弹性 (workday scaling) / 基于消息队列深度 / Prometheus 指标驱动
