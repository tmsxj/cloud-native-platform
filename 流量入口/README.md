# P2a.15 — Gateway（网关实例） API（网关 API，K8s 网关标准）+ Envoy Gateway（数据面网关）金丝雀流量分割

> 📅 2026-07-06 完成 | 验证状态: ✅ Gateway（网关）→ HTTPRoute（HTTP 路由）→ 80/20 权重金丝雀
> **术语对照**（以 `全局参考/术语表.md` 为准）：Gateway API=网关 API（Ingress 继任标准）；GatewayClass（网关实现类）=网关实现类；Gateway=网关实例（监听端口）；HTTPRoute=HTTP 路由规则；Envoy=数据面代理；Ingress=传统入口规则；CRD=自定义资源定义。

## 做了什么

1. 部署 Gateway API（网关 API，Ingress 继任标准） v1.0 CRDs（自定义资源定义）+ Envoy Gateway v1.2.0
2. 三层模型验证: GatewayClass（网关实现类）→ Gateway（网关实例）→ HTTPRoute（HTTP 路由规则）
3. 金丝雀流量分割: demo-v1 (80%) + demo-v2 (20%)
4. Envoy Proxy（数据面代理）由控制面自动管理，无需手写 Sidecar（边车代理）

## Ingress（入口规则） vs Gateway API（为什么换）

| 维度 | Ingress（传统入口） | Gateway API（新一代） |
|------|---------------------|------------------------|
| 资源模型 | 单一 Ingress 资源 | 三层分离：GatewayClass / Gateway / HTTPRoute（HTTP 路由规则） |
| 角色分工 | 运维+开发混管 | 基础设施团队管 Gateway、应用团队管 HTTPRoute（关注点分离） |
| 路由能力 | 基础 path/host 路由 | 权重金丝雀、Header 匹配、流量拆分、HTTP 方法匹配 |
| 实现绑定 | 实现相关（nginx/ traefik 注解各异） | 标准 API，多实现（Envoy Gateway / Istio / Cilium（基于 eBPF 的 CNI/网络方案））通用 |
| 本项目实例 | `K8s基础/K8s（Kubernetes，容器编排引擎）-三基石` 的 tomcat.test 暴露 | 本文件 80/20 金丝雀权重分割 |

## 架构

```
GatewayClass (eg)                        集群级 — 定义 Gateway 实现
    │
    ▼
Gateway (eg, default NS)                 命名空间级 — 监听 80 端口
    │
    ▼
HTTPRoute (demo-canary)                  路由规则 — 80/20 金丝雀
    │
    ▼
├─ Service demo-v1 (80)  ───► backend pods
└─ Service demo-v2 (20)  ───► backend pods
```

## 关键配置

```yaml
# HTTPRoute 金丝雀
spec:
  rules:
    - backendRefs:
        - name: demo-v1
          port: 80
          weight: 80      # 80% 流量到 v1
        - name: demo-v2
          port: 80
          weight: 20      # 20% 流量到 v2
      matches:
        - path:
            type: PathPrefix
            value: /
```

## 验证方式

```bash
# 1. 确认 Gateway 状态
kubectl get gateway eg -n default

# 2. 确认 HTTPRoute 状态
kubectl get httproute demo-canary -n default

# 3. 获取 Envoy Proxy IP
kubectl get svc -n envoy-gateway-system

# 4. 金丝雀验证（循环请求看响应分布）
for i in $(seq 1 20); do
  curl -s http://<envoy-ip>/ | grep version
done
# 预期: v1 返回 ~16 次, v2 返回 ~4 次
```

## 面试要点

1. **Gateway API vs Ingress**: Gateway API 是 Ingress 的继任者，角色分离（infra/application）、更丰富的路由语义
2. **三层模型**: GatewayClass（实现）→ Gateway（监听）→ HTTPRoute（路由），比 Ingress 单一资源更灵活
3. **Envoy（数据面代理） Gateway 架构**: 控制面 (envoy-gateway) + 数据面 (envoy-proxy)，类似 Istio 但更轻量
4. **金丝雀权重**: 不是精确轮询，是概率分配，大流量下趋近比例
5. **生产路线**: Gateway API 已是 GA (v1.0)，可替代 Ingress-nginx
