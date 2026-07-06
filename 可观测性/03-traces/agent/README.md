# P1.6 — Skywalking Java Agent 注入 & 全链路追踪

> 📅 2026-07-05 完成 | 验证状态: ✅ OAP 注册成功 + 调用链可视化

## 做了什么

1. 将 Skywalking Java Agent (`skywalking-agent.jar`) 通过 hostPath 挂载到 Tomcat Pod
2. 通过 `JAVA_OPTS` 注入 Agent 参数（OAP 地址、服务名、实例名）
3. 验证 OAP 控制台注册新服务 `tomcat-prod`
4. 通过 Argo Rollouts 灰度流量触发 → 调用链可视化

## 核心配置

```yaml
spec:
  containers:
    - name: tomcat
      image: 192.168.1.61/library/tomcat:9-jdk8
      env:
        - name: JAVA_OPTS
          value: >-
            -javaagent:/skywalking/agent/skywalking-agent.jar
            -Dskywalking.agent.service_name=tomcat-prod
            -Dskywalking.agent.instance_name=tomcat-prod-$(POD_IP)
            -Dskywalking.collector.backend_service=skywalking-oap.monitoring:11800
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
      volumeMounts:
        - name: skywalking-agent
          mountPath: /skywalking/agent
          readOnly: true
  volumes:
    - name: skywalking-agent
      hostPath:
        path: /opt/skywalking-agent
        type: Directory
```

## 关键设计

| 配置项 | 值 | 说明 |
|--------|-----|------|
| Agent 路径 | `/opt/skywalking-agent/skywalking-agent.jar` | 宿主机 hostPath |
| OAP gRPC | `skywalking-oap.monitoring:11800` | 跨命名空间 DNS |
| 服务名 | `tomcat-prod` | OAP 面板显示名称 |
| 元数据注入 | `POD_IP` + `POD_NAME` | 精确定位实例 |

## 验证方式

```bash
# 1. 确认 OAP 注册
kubectl exec -n monitoring skywalking-oap-0 -- \
  curl -s http://localhost:12800/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{getAllServices{name}}"}'

# 2. 确认调用链有数据
# Skywalking UI → 服务拓扑 → tomcat-prod

# 3. Argo Rollouts 灰度触发流量
# kubectl argo rollouts promote tomcat-app-agent -n tomcat-prod
```

## 面试要点

1. **Java Agent 原理**: `-javaagent` JVM 参数 → premain → 字节码增强 → 无侵入埋点
2. **hostPath vs InitContainer**: hostPath 更简单，InitContainer 更容器化，面试说两种方案
3. **跨命名空间通信**: OAP 在 monitoring NS，Tomcat 在 tomcat-prod NS，通过 `svc.ns:port` DNS 通信
4. **trace_id 传递**: Agent 自动注入 HTTP header → Loki/Promtail 正则提取 → Grafana Loki 关联看板
