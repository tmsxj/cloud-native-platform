# snownlp-observability-demo

> 基于 Kubernetes 的可观测性完整链路演示项目  
> 情感分析微服务 + 日志采集 + 调用链追踪 + 一键跳转

---

## 架构总览

```
┌────────────────────────────────────────────────────────────────┐
│                         你的浏览器                               │
│  grafana.lab.local:31716      skywalking.lab.local:31716        │
└────────┬──────────────────────────────┬─────────────────────────┘
         │                              │
  ┌──────▼──────────────────────────────▼──────────┐
  │          Ingress NGINX Controller               │
  │          NodePort: 31716                        │
  │          (Host 头路由，一台机器暴露所有服务)         │
  └──┬─────────────────────┬────────────────────────┘
     │                     │
┌────▼─────┐         ┌─────▼──────────┐
│ Grafana  │         │  SkyWalking UI │
│  :3000   │         │  :8080         │
└──┬───┬───┘         └──────┬─────────┘
   │   │                    │
   │ ┌─▼─────┐      ┌───────▼──────────┐
   │ │ Loki  │      │ SkyWalking OAP    │
   │ │ :3100 │      │ :12800 (GraphQL)  │
   │ │       │      │ :11800 (gRPC)     │
   │ └─▲─────┘      └───────▲───────────┘
   │   │                    │ gRPC 上报
   │ ┌─┴──────────────┐ ┌──┴────────────────┐
   │ │ Promtail       │ │ snownlp-demo       │
   │ │ DaemonSet      │ │ + SkyWalking Agent │
   │ │ (每节点一个)     │ │ (sw-python run)    │
   │ └─▲──────────────┘ └────────────────────┘
   │   │ 读取 /var/log/pods/
   │   │
   └───┤ Grafana Loki 数据源
       │ derivedFields: 日志中的 trace_id
       │ → 构造 SkyWalking 跳转链接
       │ → 一键查看完整调用链
```

---

## 四条数据链路

### 链路①: 应用运行
```
loadgen → POST /predict → snownlp-demo (SnowNLP 情感分析)
                              │
                              ├→ Prometheus 指标: /metrics
                              └→ 日志输出: trace_id=xxx ...
```

### 链路②: 日志采集
```
应用 print() → stdout → /var/log/pods/... → Promtail 读取
    → CRI 解析 → 提取 namespace/pod_name → 提取 trace_id
    → 推送 Loki (label: namespace, pod_name, trace_id)
```

### 链路③: trace 采集
```
请求进入 → sw_trace_middleware 创建 Entry Span (Layer=Http)
    → SkyWalking Python Agent → gRPC → OAP (skywalking-oap:11800)
    → OAP 存储 H2/Elasticsearch → UI 查询 GraphQL
```

### 链路④: 日志 traceID → SkyWalking 一键跳转（核心亮点）
```
Grafana Explore Loki:
  日志行 "trace_id=aa5e61a26efa11f18f1bba87a413a4b2"
       ↓
  Loki 数据源 derivedFields matcherRegex 匹配捕获
       ↓
  URL 构造: skywalking.lab.local:31716/trace?traceId=aa5e61a2...
       ↓
  前端展示为可点击徽章 → 一键跳转 SkyWalking 查看完整调用链
```

---

## 目录结构

```
snownlp-observability-demo/
├── README.md                         # 本文件
├── 01-app/                           # 业务应用
│   ├── app.py                        # 情感分析 FastAPI 服务
│   ├── requirements.txt              # Python 依赖
│   ├── Dockerfile                    # 镜像构建
│   ├── deployment.yaml               # K8s Deployment
│   ├── service.yaml                  # K8s Service
│   ├── loadgen.py                    # 持续压测脚本
│   └── loadgen-deployment.yaml       # 压测器 Deployment + ConfigMap
├── 02-promtail/                      # 日志采集器
│   ├── promtail-config.yaml          # Promtail ConfigMap
│   └── promtail-daemonset.yaml       # Promtail DaemonSet (含/var/log挂载)
├── 03-loki/                          # 日志存储
│   └── loki-config.yaml              # Loki ConfigMap
├── 04-grafana/                       # 可视化 + 跳转关联
│   └── loki-datasource.json          # Grafana Loki 数据源 (derivedFields)
└── 05-ingress/                       # 外部访问
    └── monitoring-ingress.yaml       # Ingress 路由规则
```

---

## 部署步骤

### 0. 前提条件
- Kubernetes 集群 (含 Ingress NGINX Controller)
- SkyWalking OAP + UI 已部署
- Grafana + Loki + Promtail 已部署
- 本地 `/etc/hosts` 添加:
  ```
  192.168.1.55  grafana.lab.local  skywalking.lab.local  snownlp.lab.local
  ```

### 1. 构建镜像
```bash
cd 01-app
docker build -t 192.168.1.61/monitoring/snownlp-demo:sw-agent .
docker push 192.168.1.61/monitoring/snownlp-demo:sw-agent
```

### 2. 部署应用 + 压测器
```bash
kubectl apply -f 01-app/deployment.yaml
kubectl apply -f 01-app/service.yaml
kubectl apply -f 01-app/loadgen-deployment.yaml
```

### 3. 更新 Promtail 配置
```bash
kubectl apply -f 02-promtail/promtail-config.yaml
kubectl rollout restart daemonset/promtail -n monitoring
```

### 4. 更新 Loki 配置
```bash
kubectl apply -f 03-loki/loki-config.yaml
kubectl rollout restart statefulset/loki -n monitoring
```

### 5. 配置 Grafana 数据源 derivedFields
```bash
# 方式1: 通过 Grafana API
curl -X POST http://grafana.lab.local:31716/api/datasources \
  -H "Content-Type: application/json" \
  -d @04-grafana/loki-datasource.json

# 方式2: 在 Grafana UI → Data Sources → Loki → Derived fields 手动配置
```

### 6. 配置 Ingress
```bash
kubectl apply -f 05-ingress/monitoring-ingress.yaml
```

---

## 验证方法

### 确认日志含 trace_id
```bash
kubectl logs -n monitoring deployment/snownlp-loadgen --tail=5
# 输出应包含:
# [11:36:37] POST /predict text=客服态度恶劣... → {"sentiment":"NEGATIVE",...}
```

### Grafana 中查看日志
1. 打开 `http://grafana.lab.local:31716`
2. Explore → 数据源选 `loki`
3. 查询: `{namespace="monitoring", pod_name=~"snownlp-demo.+"}`
4. 日志中应出现可点击的 **SkyWalking Trace** 链接

### 验证一键跳转
1. 在 Grafana 日志面板中点击 traceID 链接
2. 应跳转到 SkyWalking UI 的 trace 详情页

---

## 关键技术点

| 技术点 | 说明 |
|--------|------|
| `sw-python run` 启动方式 | 必须用 `sw-python run uvicorn ...` 而非直接 `python app.py`，否则 Agent 不会自动注入 |
| Entry Span 手动创建 | FastAPI 的 ASGI 中间件无法被 SW 自动识别，需要在 middleware 中手动 `ctx.new_entry_span()` |
| `Layer.Http` 标注 | 标注 layer 为 Http 类型，SkyWalking UI 才能正确展示 HTTP 调用链拓扑 |
| `source: filename` | Promtail regex 从文件路径提取元数据，避免受日志内容格式变化影响 |
| `allow_structured_metadata: true` | Loki 配置项，必须开启才能存储 Promtail 提取的自定义 label |
| `derivedFields` | Grafana 核心关联机制，通过正则匹配日志内容构造外链 URL |
| Ingress Host 路由 | 单 NodePort 暴露多服务，通过请求 Host 头分流 |

---

## 踩坑记录

| 问题 | 原因 | 解决 |
|------|------|------|
| 日志缺少 trace_id | Agent 未正确初始化 | 改用 `sw-python run` 启动 + 手动 Entry Span |
| Grafana 查不到日志 | pod_name label 含随机 uid | 用正则 `pod_name=~"snownlp-demo.+"` 模糊匹配 |
| Promtail 未提取 trace_id | CRI 解析后日志格式变化 | pipeline 顺序: 先 cri → 再 regex → 再 labels |
| trace 页面偶发空白 | SkyWalking SPA 前端 GraphQL 连接不稳 | 演示场景可接受，不影响架构说明 |
| gRPC 上报偶发错误 | Segment 数据格式与 OAP 不匹配 | 手动创建的 Span 需确保所有必填字段完整 |

---

## 面试演示要点

> **不要逐组件讲，画四条链路图，按数据流向说！**

1. **一张图画完架构** → 展示上面的 ASCII 架构图
2. **从请求说起** → `loadgen → POST /predict → snownlp-demo`
3. **trace 怎么产生的** → `sw_trace_middleware → gRPC → OAP → 调用链`
4. **日志怎么收集的** → `stdout → /var/log/pods → Promtail → Loki`
5. **怎么关联起来的** → `日志中 trace_id → derivedFields 正则 → URL 跳转`
6. **亮点** → 从日志发现问题 → 一键跳转调用链 → 快速定位根因
