# Grafana（可视化面板） Loki 数据源配置说明

## 这是什么

Grafana 中 Loki（日志系统） 数据源的完整配置，导入后可在 Grafana Explore 中查询 Loki 日志，
并且日志中的 `trace_id` 会自动变成可点击的 SkyWalking（APM 调用链追踪） 跳转链接。

---

## 核心机制: derivedFields（关联跳转）

这是整个可观测性链路的**最后一环**——从日志 trace_id 到 SkyWalking 的一键跳转。

### 工作流程
```
Grafana 收到 Loki 查询结果
  → 日志行: "... trace_id=aa5e61a26efa11f18f1bba87a413a4b2 ..."
  → matcherRegex 正则匹配，捕获 traceId
  → URL 中用 ${__value.raw} 替换为实际值
  → 前端渲染为可点击的 "SkyWalking Trace" 徽章/链接
  → 点击 → 跳转到 SkyWalking UI 查看完整调用链
```

### 关键字段说明

| 字段 | 值 | 说明 |
|------|-----|------|
| `url` | `http://loki.monitoring:3100` | Loki 集群内地址，Grafana 通过 proxy 模式访问 |
| `access` | `proxy` | 通过 Grafana 后端代理，不暴露 Loki 端口 |
| `matcherRegex` | `trace[_]?[iI][dD][=:]([a-fA-F0-9]{32})` | 正则匹配日志中的 trace_id，捕获 32 位 hex |
| `name` | `traceID` | 导出字段名 |
| `url` | `skywalking.lab.local:31716/trace?traceId=${__value.raw}` | 跳转链接模板，`${__value.raw}` 被替换为捕获值 |
| `urlDisplayLabel` | `SkyWalking Trace` | 前端显示的链接文本 |

### 正则详解
```
trace[_]?[iI][dD][=:]([a-fA-F0-9]{32})
│     │     ││     │   │└──────────────┘
│     │     ││     │   │  捕获 32 位十六进制 traceId
│     │     ││     │   └─ = 或 : 分隔符
│     │     ││     └─ "Id" / "id" / "ID" 等变体（大小写不敏感）
│     │     │└─ "iI" 匹配 i 或 I
│     │     └─ "dD" 匹配 d 或 D
│     └─ 可选的下划线 _
└─ 固定前缀 "trace"
```

兼容格式:
- `trace_id=aa5e61a26efa11f18f1bba87a413a4b2` ← 我们用的格式
- `traceId=aa5e61a26efa11f18f1bba87a413a4b2`
- `trace_id:aa5e61a26efa11f18f1bba87a413a4b2`

---

## 导入方式

### 方式1: Grafana API
```bash
curl -X POST http://grafana.lab.local:31716/api/datasources \
  -H "Content-Type: application/json" \
  -d @loki-datasource.json
```

### 方式2: Grafana UI
1. 打开 Grafana → Connections → Data Sources
2. 选择 Loki → 滚动到底部 Derived fields
3. 点击 Add derived field，按上述参数手动填写

---

## 验证
1. 进入 Grafana → Explore
2. 数据源选择 `loki`
3. 查询: `{namespace="monitoring", pod_name=~"snownlp-demo.+"}`
4. 日志行末尾应出现可点击的 **SkyWalking Trace** 链接
