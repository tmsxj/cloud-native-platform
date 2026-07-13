# P2b.13 — Loki（日志系统） 多租户

> 📅 2026-07-06 完成 | 验证状态: ✅ demo/fake 租户隔离 + Promtail 注入 tenant_id

## 做了什么

1. Loki: `auth_enabled: false → true`
2. Promtail: clients 加 `tenant_id: demo`
3. Grafana（可视化面板）: Loki 数据源加 `X-Scope-OrgID: demo`
4. 验证: demo 租户查询有数据，fake 租户查询为空

## 多租户原理

```
                    X-Scope-OrgID: demo
Grafana ─────────────────────────────────────► Loki
                                                    │
Promtail ──── tenant_id: demo ──────────────────────┤
                                                    │
                                                    ▼
                                         ┌─────────────────┐
                                         │  tenant "demo"   │
                                         │  ├─ streams      │
                                         │  └─ labels       │
                                         ├─────────────────┤
                                         │  tenant "fake"   │
                                         │  └─ (empty)      │
                                         └─────────────────┘
```

## 关键改动

| 组件 | 改动位置 | 改动内容 |
|------|----------|----------|
| Loki | CM `loki-config` | `auth_enabled: true` |
| Promtail | CM `promtail-config` | clients 下加 `tenant_id: demo` |
| Grafana | CM `grafana-datasources` | `httpHeaderName1: X-Scope-OrgID`, `httpHeaderValue1: demo` |

## 验证方式

```bash
# 1. 从 Loki pod 内测试 demo 租户
kubectl exec -n monitoring loki-0 -- wget -qO- --timeout=3 \
  --header='X-Scope-OrgID: demo' \
  'http://localhost:3100/loki/api/v1/label'
# 返回正常的 label 值

# 2. 测试 fake 租户 (无数据)
kubectl exec -n monitoring loki-0 -- wget -qO- --timeout=3 \
  --header='X-Scope-OrgID: fake' \
  'http://localhost:3100/loki/api/v1/label'
# 返回空 (与该租户匹配的 label 不存在)

# 3. 不带租户头
kubectl exec -n monitoring loki-0 -- wget -qO- --timeout=3 \
  'http://localhost:3100/loki/api/v1/label'
# 返回错误 (auth_enabled=true, 无租户头)
```

## Loki vs ELK 日志方案对比

| 维度 | Loki（本项目采用） | ELK（Elasticsearch + Logstash + Kibana） |
|------|-------------------|-------------------------------------------|
| 索引模型 | 仅索引 label（轻，像 Prometheus 的日志版） | 全文倒排索引（重，磁盘占用大） |
| 存储成本 | 低（chunk 可直接落对象存储 MinIO S3） | 高（ES 索引膨胀） |
| 查询语言 | LogQL（类 PromQL） | KQL / Lucene |
| 多租户 | `X-Scope-OrgID` header 原生支持（见上） | 需额外鉴权/空间隔离 |
| 适用 | K8s 日志、与 Prometheus/Grafana 同源 | 全文检索重、已有 ES 投资 |

> 本项目选 Loki：与 Prometheus/Grafana 同源、label 索引省资源、chunk 落 MinIO 对齐 LGTM 标准栈。

## 内存开销

多租户不新增 Pod（容器组），只在请求路径加租户识别。内存增量 ~50-100MB。

## 面试要点

1. **为什么需要多租户**: 同一集群服务多个团队/环境，日志隔离，防止 team-A 查到 team-B 的日志
2. **Loki 多租户实现**: X-Scope-OrgID header → limits_config → 每个租户独立的索引和存储
3. **鉴权层缺什么**: 当前只有 header 识别，无加密/签名验证。生产需加反向代理 (nginx/openresty) 做 JWT/OAuth 验证
4. **租户 vs label**: 租户是硬隔离 (跨租户不可见)，label 是同一租户内的软过滤
5. **Promtail role**: `tenant_id` 在 Promtail 端写死，推送端决定数据归属哪个租户
