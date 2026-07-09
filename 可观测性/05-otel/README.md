# 05 - OpenTelemetry 替换 SkyWalking（traces 收口 + 卸载 ES 省内存）

> 实战目标：用 **OpenTelemetry 标准栈**（OTel Collector + Jaeger）替换原 **SkyWalking OAP/UI + Elasticsearch** 链路追踪方案，
> 借机卸载 ES（单节点最大 ~792Mi），释放 worker 内存，并把 traces 收口到厂商中立的 OTLP 协议。
>
> 📅 落地日期: 2026-07-09 | 集群: kubeadm 5 节点 | 命名空间: `monitoring`

---

## 1. 为什么换？

| 痛点 | SkyWalking + ES | OpenTelemetry + Jaeger |
|------|-----------------|------------------------|
| 协议 | SkyWalking 私有协议，需 Java Agent 注入 | **OTLP 标准协议**，多语言 SDK 原生支持，后端可替换 |
| 存储 | Elasticsearch 3 节点 StatefulSet（重，单 Pod 峰值 ~792Mi） | Jaeger 内存存储（all-in-one，轻量）；也可换 Tempo/Cassandra |
| 重启副作用 | 节点重启后 `vm.max_map_count` 复位 → ES 三节点 `CrashLoopBackOff`，连带 skywalking-oap 挂 | 无 ES 依赖，重启即恢复 |
| 标准度 | Apache 顶级项目，但厂商绑定 | CNCF 毕业级，云原生事实标准，Grafana 原生友好 |

> 💡 触发点：集群 07-09 开机后实测 ES 三节点 + skywalking-oap 全部 `CrashLoopBackOff`，
> 而 Jaeger/OTel 方案零 ES 依赖 → 替换并卸载 ES **零风险、纯收益**。

---

## 2. 架构

```
  业务 Pod (任意语言 OTel SDK)
        │  OTLP/gRPC :4317 或 OTLP/HTTP :4318
        ▼
  ┌─────────────────────────────┐
  │   OTel Collector (contrib)   │  ← 集群内 OTLP 收口网关
  │   receivers: otlp(grpc+http) │
  │   processors: memory_limiter,│
  │              batch           │
  │   exporters: otlp/jaeger ────┼──► Jaeger (all-in-one, 内存存储, UI :16686)
  │              debug (日志)    │
  └─────────────────────────────┘
        │
        ▼
  Grafana  ← Jaeger 数据源 (type=jaeger, url=http://jaeger.monitoring:16686)

  关键接线点：业务只需把 OTLP 端点指向 `otel-collector.monitoring:4317/4318`，
  后端是 Jaeger 还是 Tempo 对业务**完全透明**（这也是替换 SkyWalking 的核心收益）。
```

---

## 3. 部署清单（本目录）

| 文件 | 作用 | 镜像（Harbor 离线） |
|------|------|---------------------|
| [`jaeger.yaml`](./jaeger.yaml) | Jaeger all-in-one 后端（默认启用 OTLP receiver + UI :16686），内存存储 | `jaegertracing/jaeger:2.14.1` |
| [`otel-collector.yaml`](./otel-collector.yaml) | OTel Collector 网关：接收 OTLP → 导出 Jaeger + debug | `monitoring/opentelemetry-collector-contrib:0.152.1` |
| [`otel-demo-app.yaml`](./otel-demo-app.yaml) | 演示应用：周期生成 trace 并经 OTLP/HTTP 投递到 Collector | `library/alpine_curl` |
| [`_grafana-datasources.yaml`](./_grafana-datasources.yaml) | Grafana 预置数据源 ConfigMap（在 Prometheus/Loki 基础上**新增 Jaeger**） | — |

> 部署：`kubectl apply -f jaeger.yaml -f otel-collector.yaml -f otel-demo-app.yaml`
> Grafana 数据源：先 `kubectl apply -f _grafana-datasources.yaml`，再 `kubectl -n monitoring rollout restart deployment/grafana`。

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
> 不可用其作 demo（已弃用）。标准 SDK 或裸 OTLP 才是正确路径。

---

## 5. 验证（端到端已通 ✅）

```bash
# 1) Collector / Jaeger / demo 全部 Running
kubectl -n monitoring get pods -l 'app in (jaeger,otel-collector,otel-demo-app)'

# 2) 业务侧日志持续 200（demo 每 5s 投递）
kubectl -n monitoring logs deploy/otel-demo-app --tail=3
# emit http=200 ...

# 3) Jaeger 已出现服务（含手动注入的 manual-demo 与 demo 程序 otel-demo-app）
kubectl -n monitoring get --raw '/api/v1/namespaces/monitoring/services/jaeger:16686/proxy/api/services'
# {"data":["jaeger","manual-demo","otel-demo-app"],"total":3,...}

# 4) 浏览器打开 Jaeger UI 搜 service=otel-demo-app → 看到 process-order 调用链
#    https://jaeger.lab.local  (走 monitoring-ingress，已移除 skywalking.lab.local)

# 5) Grafana → Explore → 数据源选 Jaeger → 搜 otel-demo-app，同样可见 trace
```

> 后端链路也曾用 `_verify2.yaml` 手动 `curl -X POST .../v1/traces` 注入 `manual-demo` 验证 Collector→Jaeger 100% 通。

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

并清理 Ingress：`monitoring-ingress` 原含 `skywalking.lab.local` 路由，已编辑移除（见 `项目实战/可观测性/monitoring-ingress.yaml` 同源配置）。

---

## 7. Grafana 接入 Jaeger 数据源

Grafana 12.3.1 仍内置 `jaeger` 数据源类型。在预置 ConfigMap `grafana-datasources` 追加：

```yaml
      - name: Jaeger
        type: jaeger
        access: proxy
        url: http://jaeger.monitoring:16686
        editable: false
```

`kubectl apply` 后 **restart grafana** 使其重新加载预置（数据源存于 NFS PVC，重启不丢）。
完整 CM 见 [`_grafana-datasources.yaml`](./_grafana-datasources.yaml)。

---

## 8. 关键经验

1. **OTLP 是 traces 的事实标准**：业务只认 Collector 端点，后端 Jaeger/Tempo 可随时替换，彻底告别 SkyWalking 私有协议绑定。
2. **离线环境优先裸 OTLP/JSON 验证链路**，再上语言 SDK，避免运行时 `pip install` 偶发失败卡进度。
3. **ES 是内存大户**：trace 存储若非必须长期留存，Jaeger 内存/或轻量后端更省资源；确需持久化可后续接 Tempo+Cassandra。
4. **scp 到 m1 `/tmp` 注意权限**：`/tmp` 下 root 创建的文件非 root SSH 用户无法覆盖，须用新文件名或 scp 到用户目录再 sudo。
