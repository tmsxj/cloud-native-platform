# 03-traces — 分布式追踪

> 本目录对应**方案 A（Prometheus + Loki + SkyWalking（APM 调用链追踪） + Elasticsearch）**的分布式追踪组件。SkyWalking OAP/UI 当前未运行（为省资源已卸载），但 manifest 仍保留，可随时部署切回。
> 方案 B（当前运行）的追踪见 [`../05-otel/README.md`](../05-otel/README.md)（OpenTelemetry + Tempo（链路追踪后端） + MinIO）。

## 什么是分布式追踪

分布式追踪（Distributed Tracing）解决的是"**一个请求跨多个服务，到底卡在哪一步、哪次调用慢**"的问题。核心概念：

- **Trace（调用链）**：一次完整请求从头到尾的所有调用集合，用全局 `trace_id` 串联。
- **Span（跨度）**：Trace 里的一个具体调用单元（一次 HTTP/RPC/SQL），含起止时间、状态、父子关系（`span_id` / `parent_span_id`）。
- **OTLP（OpenTelemetry 协议）**：可观测性数据采集标准 OTel 定义的传输协议（gRPC 4317 / HTTP 4318），业务侧只管吐 OTLP，后端可接 Tempo/Jaeger。
- **Agent 注入**：无需改业务代码，通过 Java Agent（`-javaagent`）或 Sidecar（边车代理） 自动埋点，采集 Span 上报。

本目录保留了**两套追踪实现**（方案 A 与方案 B），目的是对比不同技术路线的取舍，下面用一张表说清。

## 两套追踪方案对比（为什么有两套）

| 维度 | 方案 A：SkyWalking | 方案 B（当前运行）：OTel + Tempo |
|------|--------------------|-----------------------------------|
| 埋点方式 | Java Agent 字节码注入（`-javaagent`） | OpenTelemetry SDK / 自动埋点，吐 OTLP |
| 数据协议 | SkyWalking 私有协议 | OTLP（标准，厂商无关） |
| 存储后端 | Elasticsearch（ES）3 节点 | Tempo + MinIO S3（bucket=tempo） |
| 查询/关联 | SkyWalking UI + Grafana derivedFields 跳 ES | Grafana Tempo 数据源，`trace_id` 关联 Loki 日志 |
| 资源占用 | OAP + ES 较重（为省资源已卸载） | otel-collector + Tempo 更轻，全栈 S3 化 |
| 适用场景 | 纯 Java 微服务、要 APM 拓扑图 | 多语言、追求标准与轻量、与 Loki 同源 MinIO |
| 本项目状态 | manifest 保留，可随时切回 | 当前运行态 |

**演进路线**：Jaeger（链路追踪） 内存版（先验证 OTLP 通不通）→ Tempo + MinIO S3（LGTM 生产标准）→ Loki 同切 MinIO（全栈 S3 化，统一对象存储）。

## 方案 A — SkyWalking 链路

- [`agent/README.md`](./agent/README.md) — SkyWalking Java Agent 注入（P1.6），Tomcat `-javaagent` 方式
- [`agent/tomcat-skywalking-deploy.yaml`](./agent/tomcat-skywalking-deploy.yaml) — 注入后的 Tomcat 部署清单
- 存储后端：Elasticsearch 3 节点（见 [`../04-es-storage/README.md`](../04-es-storage/README.md)）
- Grafana（可视化面板） 关联：通过 `derivedFields → SkyWalking` 跳转调用链

## 方案 B（当前运行）— OTel + Tempo 链路

```
业务 Pod（OTLP 4317/4318）
      │
      ▼
otel-collector.monitoring   ← 统一 OTLP 收口网关（对业务透明）
      │
      ▼
Tempo（存储后端 = MinIO S3, bucket=tempo）
      │
      ▼
Grafana（Tempo 数据源，trace_id 关联 Loki 日志）
```

演进：Jaeger（链路追踪） 内存版（验证 OTLP）→ Tempo + MinIO S3（LGTM 生产标准）→ Loki 同切 MinIO（全栈 S3 化）。
