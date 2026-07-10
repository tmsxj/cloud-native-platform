# Istio 服务网格部署（离线 / Harbor 镜像）

> 版本：Istio **1.30.2**（profile=default，控制面 istiod + ingress-gateway）
> 集群：kubeadm v1.28.15（5 节点，聚焦模式，master 内存红线 → 控制面只落 worker）
> 镜像源：`docker.io/istio/*` → 经 `外网资源同步/sync_from_us.ps1` 入 Harbor `192.168.1.61/istio/*`
> 验证结论：`istiod` + `istio-ingressgateway` Running；demo 注入 2/2；STRICT mTLS 生效；L7 黄金指标可采；熔断/重试/超时策略就绪。

## 1. 为什么选 profile=default + 1.30.2

- `default` profile 仅装 `istiod`（控制面）+ `istio-ingressgateway`（入口网关），不含 Kiali/Grafana/Prometheus 等 addon，最省资源，契合聚焦模式。
- 1.30.2 是当前稳定版，兼容 k8s 1.28；`istioctl manifest generate` 渲染出纯 YAML，便于离线 apply 与镜像改写。

## 2. 离线镜像清单（需同步进 Harbor）

控制面与数据面（hub 覆盖为 `192.168.1.61/istio`，tag `1.30.2`）：

```
docker.io/istio/pilot:1.30.2     →  192.168.1.61/istio/pilot:1.30.2
docker.io/istio/proxyv2:1.30.2   →  192.168.1.61/istio/proxyv2:1.30.2
```

istiod 的 grpc-bootstrap init 容器用到（`busybox` 改写为 Harbor 路径）：

```
busybox:1.28   →  192.168.1.61/library/busybox:1.28
```

> ⚠️ 镜像同步坑：`istio` 源镜像 subpath 为 `istio/pilot`、`istio/proxyv2`，配合 `-HarborProject istio` 落点干净（`192.168.1.61/istio/pilot`），**不会**像 linkerd 那样产生双路径。
> 但 `sync_from_us.ps1` 脚本带 `set -e`，首跑 pilot 已 push 后 proxyv2 的 tag 步骤中途退出（exit 1）会导致 proxyv2 未推。
> 解决：在 H1 用 `docker tag istio/proxyv2:1.30.2 192.168.1.61/istio/proxyv2:1.30.2 && docker push` 补推。

## 3. 渲染 + 安装（离线）

```powershell
# 渲染（hub/tag 覆盖为 Harbor 路径，关闭 ingressgateway 自动扩缩以省资源）
istioctl manifest generate --set profile=default `
  --set "values.global.hub=192.168.1.61/istio" --set "values.global.tag=1.30.2" `
  --set "values.global.imagePullPolicy=IfNotPresent" `
  --set "values.gateways.istio-ingressgateway.autoscaleEnabled=false" `
  > istio-final.yaml

# 入口网关 init 容器镜像 busybox:1.28 改为 Harbor 路径（在 m1 上用 sed 改写最稳）
ssh m1 "sudo sed -i 's|image: busybox:1.28|image: 192.168.1.61/library/busybox:1.28|g' /tmp/istio-final.yaml"

# 必须先建命名空间再 apply（manifest 不自带 ns，否则报 namespaces \"istio-system\" not found）
scp istio-final.yaml m1:/tmp/
ssh m1 "echo '123' | sudo -S bash -c 'export KUBECONFIG=/etc/kubernetes/admin.conf; \
  kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -; \
  kubectl label namespace istio-system istio-injection=disabled --overwrite; \
  kubectl apply -f /tmp/istio-final.yaml'"
```

> 控制面 Deployment `istiod` / `istio-ingressgateway` 默认无 master taint 的 toleration，天然只调度到 worker，护住 master 内存红线。
> 早期有 `FailedMount` 瞬时抖动（secret cache 同步超时），已自愈，Pod 正常 Running。

## 4. 验证：控制面

```bash
kubectl get pods -n istio-system -o wide
# NAME                                   READY  STATUS   NODE
# istiod-6d6c9c45cf-pmnjb                1/1    Running  worker2   (image 192.168.1.61/istio/pilot:1.30.2)
# istio-ingressgateway-f7485bfb6-gkvff   1/1    Running  worker2   (image 192.168.1.61/istio/proxyv2:1.30.2)

kubectl describe pod -n istio-system -l app=istiod
# Pulling image "192.168.1.61/istio/pilot:1.30.2"  →  Successfully pulled ... in 3.997s
```

## 5. 验证：demo（同构于 Linkerd demo，便于双网格对比）

`istio-demo.yaml`（命名空间 `istio-injection: enabled`）+ `istio-policy.yaml`（mTLS + 流量治理）：

```bash
kubectl apply -f istio-demo.yaml
kubectl apply -f istio-policy.yaml
kubectl get pods -n istio-demo -o wide
# NAME                          READY  STATUS   NODE
# client-5769d5c884-p5vkc       2/2    Running  worker1   (app + istio-proxy)
# nginx-backend-7455d95458-4t2nk 2/2   Running  worker1
# nginx-backend-7455d95458-gcbpv 2/2   Running  worker2
# → 2/2 证明 sidecar 注入成功（Envoy）
```

### 5.1 mTLS（STRICT，双向验证）

```bash
kubectl get peerauthentication -n istio-demo
# NAME     MODE     AGE
# default  STRICT   7s
```

- **正向**：网格内 client 经 Envoy 访问 backend 正常（`istio_requests_total` 计数全 200）。
- **反向（强证）**：用一个**非网格** Pod 明文直连 backend PodIP:80 被拒：

```
# kubectl run nomesh --rm -n istio-demo --image=192.168.1.61/library/busybox:1.28 --command -- wget http://<backendPodIP>:80/
wget: can't connect to remote host (10.0.3.39): Connection refused
WGET_EXIT=1
```

→ STRICT mTLS 生效：无身份明文流量一律拒绝。

### 5.2 L7 黄金指标（Envoy 自定义计数器）

Istio 的 L7 指标以 `istiocustom.istio_requests_total`（及 request_duration / request_bytes / response_bytes）形式暴露：

```
istiocustom.istio_requests_total...destination_service.nginx-backend.istio-demo.svc.cluster.local...response_code.200...: 90
istiocustom.istio_request_duration_milliseconds...response_code.200...:
   P0(1.05) P50(2.07) P75(3.05) P90(4.05) P95(4.05) P99(4.05) P100(4.05)
istiocustom.istio_request_bytes...:   P50(874) ...
istiocustom.istio_response_bytes...:  P50(871) ...
```

→ 请求数、成功率（200）、延迟分位（P50/P90/P99）、请求/响应字节全部可采，即 L7 观测达成。

### 5.3 流量治理（Istio 区别于 Linkerd 的核心）

`istio-policy.yaml` 已下发且生效（从 Envoy outbound 集群可见 outlier 配置）：

```yaml
# DestinationRule：连接池限制 + 熔断（离群实例 ejection）
trafficPolicy:
  connectionPool: { tcp: { maxConnections: 1 }, http: { http1MaxPendingRequests: 1 } }
  outlierDetection: { consecutive5xxErrors: 3, interval: 30s, baseEjectionTime: 30s }
# VirtualService：重试 + 超时（故障容错）
retries: { attempts: 3, perTryTimeout: 2s, retryOn: "5xx,reset,connect-failure,refused-stream" }
timeout: 5s
```

Envoy outbound 集群已带熔断元数据（验证证据）：

```
outbound|80||nginx-backend.istio-demo.svc.cluster.local::outlier::success_rate_average::-1
outbound|80||nginx-backend.istio-demo.svc.cluster.local::outlier::success_rate_ejection_threshold::-1
```

## 6. 能力小结（对比 Linkerd 用）

| 维度 | Istio 表现 |
|------|------|
| mTLS | PeerAuthentication 可设 PERMISSIVE/STRICT；STRICT 下明文直连被拒（已强证）；身份为 SPIFFE ID |
| 注入 | 命名空间标签 `istio-injection: enabled`，自动注入 Envoy sidecar（2/2） |
| 黄金指标 | `istio_requests_total` + 延迟/字节分位；需 Prometheus/Kiali 聚合（本部署未装 addon，原始计数器已可采） |
| 观测 UI | 默认无；需额外装 Kiali/Grafana（聚焦模式暂略，离线镜像较多） |
| 资源占用 | 较重（Envoy 用 C++，~50-100MB/sidecar + istiod 控制面），但控制面仅落 worker 可控 |
| 流量治理 | 强：VirtualService 重试/超时/熔断、DestinationRule 连接池/离群检测、Gateway、流量切分 |
| 熔断/限流 | 原生支持（outlierDetection + connectionPool），Linkerd 无 |
| 入口网关 | 自带 istio-ingressgateway，Linkerd 需配合第三方 ingress |
