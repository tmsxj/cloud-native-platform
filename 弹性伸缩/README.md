# P2a.11 — KEDA 事件驱动自动伸缩

> 📅 2026-07-05 完成 | 验证状态: ✅ 3 Pod Running + Cron ScaledObject Ready + 底层 HPA 自动生成

## 做了什么

1. 离线部署 KEDA 2.16.1（3 镜像: us→h1→Harbor→containerd）
2. 部署 Cron ScaledObject 演示 — 工作日 9-18 自动扩缩
3. KEDA 自动生成底层 HPA，无缝对接 metrics-server

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
4. **与传统 CronJob 区别**: CronJob 是 Job 执行，KEDA Cron Scaler 是调整 Deployment 副本数
5. **生产场景**: 工作日弹性 (workday scaling) / 基于消息队列深度 / Prometheus 指标驱动
