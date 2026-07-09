# 03-traces — 分布式追踪

> 本目录对应**方案 A（Prometheus + Loki + SkyWalking + Elasticsearch）**的分布式追踪组件。SkyWalking OAP/UI 当前未运行（为省资源已卸载），但 manifest 仍保留，可随时部署切回。
> 方案 B（当前运行）的追踪见 [`../05-otel/README.md`](../05-otel/README.md)（OpenTelemetry + Tempo + MinIO）。

## 方案 A — SkyWalking 链路

- [`agent/README.md`](./agent/README.md) — SkyWalking Java Agent 注入（P1.6），Tomcat `-javaagent` 方式
- [`agent/tomcat-skywalking-deploy.yaml`](./agent/tomcat-skywalking-deploy.yaml) — 注入后的 Tomcat 部署清单
- 存储后端：Elasticsearch 3 节点（见 [`../04-es-storage/README.md`](../04-es-storage/README.md)）
- Grafana 关联：通过 `derivedFields → SkyWalking` 跳转调用链

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

演进：Jaeger 内存版（验证 OTLP）→ Tempo + MinIO S3（LGTM 生产标准）→ Loki 同切 MinIO（全栈 S3 化）。
