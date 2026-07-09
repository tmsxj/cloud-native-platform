# 05 - OpenTelemetry + LGTM 完整可观测性栈（traces 收口 + 卸 ES + 对象存储）

> 实战目标：用 **OpenTelemetry 标准栈** 收口 traces，并把后端对齐到 **LGTM** 业界标准组合
> （**L**oki + **G**rafana + **T**empo + **M**imir/对象存储）。
> 本期先完成 **T = Tempo + MinIO(S3)**，承接原 SkyWalking+ES 的链路追踪，并卸载 Elasticsearch 释放内存。
>
> 📅 落地日期: 2026-07-09 | 集群: kubeadm 5 节点 | 命名空间: `monitoring`
> 🔁 演进: 本目录先以 `Jaeger 内存版` 验证 OTLP 链路 → 再升级为 `Tempo + MinIO` 对齐 LGTM 生产标准（本文档为最终版）

---

## 1. 为什么是 LGTM？

可观测性三支柱的"后端选型"和 CICD 的"方案选型"同理，业界已沉淀出事实标准组合。OTel 只管**采集+传输（OTLP）**，后端可插拔：

| 组合 | 后端三件套 + UI | 定位 |
|------|----------------|------|
| ES 系（老牌） | Elasticsearch + Kibana | 重资产，搜索强但吃内存（原 SkyWalking+ES 即此路） |
| **LGTM（事实标准 ✅）** | Prometheus(Mimir)+Loki+**Tempo**+Grafana | 开源现代派，分治、可水平扩展、与 OTel 绑定最深 |
| 商业 SaaS | Datadog / New Relic | 省心、贵 |
| 一体化 | SigNoz (ClickHouse) | 新兴、对 OTel 最原生 |

> LGTM 的灵魂：**Tempo 用对象存储（S3）做 trace 后端**，而非内存。这样 trace 可长期留存、可水平扩展，
> 且 Grafana 一个 UI 看 metrics/logs/traces 三件套。本项目已有 Prometheus+Loki+Grafana，补上 **Tempo+MinIO** 即凑齐 LGTM。

---

## 2. 架构（最终版：Tempo + MinIO）

```
  业务 Pod (任意语言 OTel SDK)
        │  OTLP/gRPC :4317 或 OTLP/HTTP :4318
        ▼
  ┌─────────────────────────────┐
  │   OTel Collector (contrib)   │  ← 集群内 OTLP 收口网关（协议/后端解耦点）
  │   receivers: otlp(grpc+http) │
  │   processors: memory_limiter,│
  │              batch           │
  │   exporters: otlp/tempo ─────┼──► Tempo (单体 -target=all, 3.0)
  │              debug (日志)    │        │ 接收 OTLP :4317/4318
  └─────────────────────────────┘        │ 存储 backend: s3
                                          ▼
                                    MinIO (S3, bucket=tempo, PVC 5Gi)
                                          ▲
  Grafana  ◄── Tempo 数据源 (type=tempo, url=http://tempo.monitoring:3200)

  关键接线点：业务只需把 OTLP 端点指向 `otel-collector.monitoring:4317/4318`，
  后端是 Jaeger 还是 Tempo（内存/S3）对业务**完全透明**。
```

---

## 3. 部署清单（本目录）

| 文件 | 作用 | 镜像（Harbor 离线） |
|------|------|---------------------|
| [`minio.yaml`](./minio.yaml) | MinIO 对象存储（Tempo 的 S3 后端；Loki/Mimir 亦可复用同一实例） | `minio/minio:RELEASE.2025-09-07T16-13-09Z` + `minio/mc:latest`(建 bucket) |
| [`tempo.yaml`](./tempo.yaml) | Grafana Tempo 单体（3.0, `-target=all`）：OTLP receiver + S3 存储 + 查询 :3200 | `grafana/tempo:latest` |
| [`otel-collector.yaml`](./otel-collector.yaml) | OTel Collector 网关：接收 OTLP → 导出 Tempo + debug | `monitoring/opentelemetry-collector-contrib:0.152.1` |
| [`otel-demo-app.yaml`](./otel-demo-app.yaml) | 演示应用：周期生成 trace 并经 OTLP/HTTP 投递到 Collector | `library/alpine:latest`(裸 curl，零运行时安装) |
| [`jaeger.yaml`](./jaeger.yaml) | ⚠️ 历史参考：早期用的 Jaeger 内存版（已弃用，被 Tempo 替换） | `jaegertracing/jaeger:2.14.1` |
| [`_grafana-datasources.yaml`](./_grafana-datasources.yaml) | Grafana 预置数据源 ConfigMap（Prometheus/Loki 基础上**新增 Tempo**） | — |

> 部署顺序（依赖：minio 先起，tempo 的 initContainer 等 minio 建 bucket）：
> ```bash
> kubectl apply -f minio.yaml
> kubectl apply -f tempo.yaml
> kubectl apply -f otel-collector.yaml
> kubectl apply -f otel-demo-app.yaml
> kubectl apply -f _grafana-datasources.yaml && kubectl -n monitoring rollout restart deployment/grafana
> ```

---

## 4. 演示应用：标准 trace 怎么产生？

### 4.1 离线环境的最简做法（本目录 `otel-demo-app.yaml`）

集群 Pod 有外网，但 m1 无 docker/nerdctl（仅 `ctr`），无法 build 自带 OTel SDK 的镜像；
而 `pip install opentelemetry` 在运行时偶发失败。因此演示程序**用裸 OTLP/HTTP(JSON) + curl 直接投递**，
零运行时安装，等价于标准 SDK 的 `BatchSpanProcessor → OTLPSpanExporter`：

```sh
# 每 5s 生成 1 条 trace：父 span process-order + 子 span db-query / call-payment
cat > /tmp/t.json <<JSON
{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"otel-demo-app"}}]},
"scopeSpans":[{"scope":{"name":"demo"},"spans":[
{"traceId":"<32hex>","spanId":"<16hex>","name":"process-order","kind":1,"startTimeUnixNano":"...","endTimeUnixNano":"..."},
{"traceId":"...","spanId":"<16hex>","parentSpanId":"<父16hex>","name":"db-query","kind":1,...},
{"traceId":"...","spanId":"<16hex>","parentSpanId":"<父16hex>","name":"call-payment","kind":1,...}
]}]}]}
JSON
curl -s -X POST http://otel-collector.monitoring:4318/v1/traces \
  -H "Content-Type: application/json" -d @/tmp/t.json
```

### 4.2 真实业务的标准做法（任意语言）

只要 SDK 把 span 导出到 Collector 即可，后端对业务透明：

```bash
# 通用环境变量（OTel 语义约定，所有语言 SDK 都认）
export OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.monitoring:4317   # 或 :4318 走 HTTP
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc          # grpc | http/protobuf
export OTEL_SERVICE_NAME=my-service
export OTEL_TRACES_EXPORTER=otlp
```

- Python：`pip install opentelemetry-api opentelemetry-sdk opentelemetry-exporter-otlp-proto-http`
  → `OTLPSpanExporter(endpoint="http://otel-collector.monitoring:4318", insecure=True)`
- Java：挂 `-javaagent:opentelemetry-javaagent.jar`（无需改代码）
- Go / Node / .NET：对应官方 SDK，endpoint 指向 Collector 即可

> ⚠️ 踩坑：谷歌 `microservices-demo` 的 frontend 用自研栈（jaeger/stackdriver），**不读** `OTEL_EXPORTER_OTLP_ENDPOINT`，
> 不可用其作 demo。标准 SDK 或裸 OTLP 才是正确路径。

---

## 5. 验证（端到端已通 ✅）

```bash
# 1) 组件全部 Running
kubectl -n monitoring get pods | grep -E 'minio|tempo|otel-collector|otel-demo-app'
# minio-*** 1/1 Running | tempo-*** 1/1 Running | otel-collector-*** 1/1 | otel-demo-app-*** 1/1

# 2) 业务侧日志持续 200（demo 每 5s 投递）
kubectl -n monitoring logs deploy/otel-demo-app --tail=3
# emit http=200 ...

# 3) MinIO bucket 已写入（证明 Tempo → S3 对象存储连通）
kubectl -n monitoring run mc-verify --rm -i --restart=Never --image=192.168.1.61/minio/mc:latest \
  --command -- sh -c "mc alias set m http://minio.monitoring:9000 minioadmin minioadmin; mc ls --recursive m/tempo"
# 出现 work.json / block 目录 = S3 写入成功

# 4) 按 trace id 直接查询（确证可查，live-store + S3 均可）
kubectl -n monitoring run tv --rm -i --restart=Never --image=192.168.1.61/library/alpine:latest \
  --command -- sh -c "apk add -q curl>/dev/null 2>&1; curl -s http://tempo.monitoring:3200/api/traces/<traceID>"
# 返回 batches[].spans[] = process-order / db-query / call-payment ✅

# 5) Tempo search（基于 block 索引，trace flush 到 S3 后可见，约 5min 延迟）
curl http://tempo.monitoring:3200/api/search   # {"traces":[{"traceID":...}],...}

# 6) Grafana → Explore → 数据源选 Tempo → 搜 service=otel-demo-app，可见完整调用链
```

> 注：Tempo 3.0 单体（`-target=all`）以 `live_store`(写路径) + `backend_scheduler`(压缩) 取代旧 `ingester`/`compactor`；
> 启动初期 backend worker 报 `no jobs found` 属正常噪音（尚无 block 需压缩），`/ready` 通过即健康。

---

## 6. 卸载 SkyWalking + Elasticsearch（释放内存）

原本 SkyWalking/ES 以**裸 manifest**（非 Helm）部署在 `monitoring`，直接删：

```bash
NS=monitoring
kubectl -n $NS delete deploy skywalking-oap skywalking-ui
kubectl -n $NS delete sts elasticsearch
kubectl -n $NS delete svc elasticsearch elasticsearch-headless skywalking-oap skywalking-ui
kubectl -n $NS delete pvc data-elasticsearch-0 data-elasticsearch-1 data-elasticsearch-2   # 释放 ~6Gi local-path
kubectl -n $NS delete servicemonitor skywalking-oap
```

并清理 Ingress：`monitoring-ingress` 原含 `skywalking.lab.local` 路由，已编辑移除。

---

## 7. Grafana 接入 Tempo 数据源（LGTM 的 G 接 T）

Grafana 原生支持 `tempo` 数据源类型。在预置 ConfigMap `grafana-datasources` 追加：

```yaml
      - name: Tempo
        type: tempo
        access: proxy
        url: http://tempo.monitoring:3200
        editable: false
```

`kubectl apply` 后 **restart grafana** 使其重新加载预置（数据源存于 NFS PVC，重启不丢）。
完整 CM 见 [`_grafana-datasources.yaml`](./_grafana-datasources.yaml)。

---

## 8. 关键经验

1. **OTLP 是 traces 的事实标准**：业务只认 Collector 端点，后端 Jaeger/Tempo/对象存储可随时替换，彻底告别 SkyWalking 私有协议绑定。
2. **LGTM 是开源可观测性事实标准**：Tempo 用 S3 对象存储做 trace 后端，可长期留存+水平扩展；本项目以 MinIO 提供 S3，与已有 Prometheus/Loki/Grafana 凑齐 LGTM。
3. **离线环境优先裸 OTLP/JSON 验证链路**，再上语言 SDK，避免运行时 `pip install` 偶发失败卡进度。
4. **Tempo 3.0 配置范式变了**：`live_store` + `backend_scheduler` 替代旧 `ingester`/`compactor`；`storage.trace.backend: s3` 指向 MinIO，bucket 需预建（用 `mc` initContainer）。
5. **scp 到 m1 `/tmp` 注意权限**：root 创建的文件非 root SSH 用户无法覆盖，须用新文件名或 scp 到用户目录再 sudo。
6. **改 Collector 导出目标后务必 `kubectl apply` ConfigMap 再 `rollout restart`**：仅 restart 不会加载新 CM（曾因此连不上旧 Jaeger 报错）。
