# K8s 三基石补全：HPA · 存储 · Ingress

---

> **当前状态 (2026-07-03)**：CI/CD 三方案 ✅，可观测性三支柱 ✅，密钥理论 ✅，三套 K8s 发布策略 ✅，K8s 三基石 ✅ —— DevOps/SRE 面试体系核心模块全部闭环！

---

## 一、补全前：当前覆盖面评估

| 面试模块 | 状态 | 覆盖深度 |
|----------|:----:|----------|
| CI/CD（Jenkins/GitLab CI + ArgoCD + Rollouts） | ✅ | 三方案 + 灰度发布，可演练 |
| 可观测性（Prometheus/Grafana/Loki/Skywalking） | ✅ | 三支柱+链路追踪，集群已部署 |
| 镜像仓库 + 扫描 | ✅ | Harbor + Trivy 离线扫描 |
| 多环境 + 配置管理 | ✅ | Kustomize overlays（dev/staging/prod） |
| 密钥管理 | ✅ 理论 | Sealed Secrets 理论 + 配置模板就绪 |
| 私有化部署实战 | ✅ | HiAgent 全流程 |
| --- | --- | --- |
| **弹性伸缩 HPA/VPA** | ✅ 已完成 | CPU 50% 触发，min=1 max=5，tomcat-app 运行中 |
| **存储持久化 PV/PVC/StorageClass** | ✅ 已完成 | NFS PV(5Gi,RWX) + PVC 绑定 + Pod 持久性验证通过 |
| **Ingress 网络管理** | ✅ 已完成 | tomcat.test → 192.168.1.55:80，nginx-ingress 路由中 |

---

## 二、待补模块一：弹性伸缩 HPA/VPA

### 2.1 面试场景

> "你们服务遇到流量高峰时怎么处理？"
> "HPA 的原理是什么？基于什么指标？"
> "HPA 和 VPA 的区别？什么时候用哪个？"

### 2.2 核心知识点

| 知识点 | 说明 |
|--------|------|
| **HPA (Horizontal Pod Autoscaler)** | 根据 CPU/内存/自定义指标自动增减 Pod 副本数 |
| **Metrics Server** | K8s 内置指标聚合层，HPA 的数据来源 |
| **自定义指标 HPA** | 基于 Prometheus Adapter 从 Prometheus 指标驱动扩缩 |
| **VPA (Vertical Pod Autoscaler)** | 自动调整 Pod 的 CPU/Memory request/limit（垂直伸缩） |
| **KEDA** | 事件驱动自动伸缩（Kafka 消息堆积 → 扩容），HPA 的升级版 |

### 2.3 HPA 决策逻辑（一句话说清楚）

```text
当前负载 / 目标阈值 × 当前副本数 = 期望副本数

例：当前 CPU 80%，目标 50%，3 副本
    期望 = ceil( 80/50 × 3 ) = ceil(4.8) = 5 副本
```

### 2.4 落地目标

```
在 tomcat-app DEV 环境上：
  1. 安装 Metrics Server（如集群未装）
  2. 创建 HPA 资源，基于 CPU 75% 触发，min=1, max=5
  3. 使用 Apache Bench 或 hey 压测触发扩容
  4. kubectl top pods + kubectl describe hpa 观察扩缩过程
  5. 记录默认缩减冷却期 (--horizontal-pod-autoscaler-downscale-stabilization=5m)
```

### 2.5 面试速答模板

| 问题 | 一句话 |
|------|--------|
| HPA 怎么工作的？ | Metrics Server 每 15s 采集指标 → HPA Controller 每 15s 计算 desiredReplicas → 触发 Scale 子控制器调整副本数 |
| 用什么指标？ | CPU/内存（默认），配合 Prometheus Adapter 可以扩自定义指标如 QPS |
| HPA 和 VPA 区别？ | HPA 水平扩（加 Pod），VPA 垂直扩（加大单个 Pod 资源）。生产环境 HPA 常用，VPA 适合数据库等无法水平扩展的工作负载 |
| 缩容冷却多久？ | 默认 5 分钟稳定期，防止抖动 |

---

## 三、待补模块二：存储 PV/PVC/StorageClass

### 3.1 面试场景

> "PV 和 PVC 是什么关系？绑定机制是什么？"
> "有状态服务怎么部署的？"
> "StorageClass 动态供给的原理？"

### 3.2 核心知识点

| 知识点 | 说明 |
|--------|------|
| **PV (PersistentVolume)** | 集群级存储资源，管理员创建或 StorageClass 动态创建 |
| **PVC (PersistentVolumeClaim)** | 用户对存储的请求，类似"申请一块存储" |
| **StorageClass** | 定义存储"类别"（NFS/SSD/local），配合 Provisioner 动态创建 PV |
| **动态供给** | 用户创建 PVC → StorageClass 自动调 Provisioner 建 PV |
| **StatefulSet** | 有状态应用控制器（每个 Pod 独立身份 + 独立 PVC，扩缩保持编号） |

### 3.3 PV/PVC 绑定机制（核心逻辑）

```text
PVC 声明需求:       集群中查找匹配 PV:
  容量: 10Gi    →      容量 ≥ 10Gi
  访问模式: RWO  →      访问模式匹配
  StorageClass: nfs →      SC 相同（或都为空）

匹配成功 → 一对一绑定 → Pod 挂载 PVC 使用
匹配失败 → PVC Pending（如开启动态供给则自动建 PV）
```

### 3.4 落地目标

```
在你的 NFS 集群环境上：
  1. 创建 NFS StorageClass（使用 nfs-subdir-external-provisioner）
  2. 创建 PVC 申请 5Gi
  3. 将 tomcat 日志目录挂载到 PVC
  4. 验证：删除 Pod 重建后数据不丢失
  5. 记录 PV → PVC → Pod volumeMount 整条链
```

### 3.5 面试速答模板

| 问题 | 一句话 |
|------|--------|
| PV 和 PVC 怎么绑定？ | PVC 声明容量+访问模式 → K8s 查找匹配的 PV → 一对一绑定。没有匹配 PV 且 StorageClass 开启动态供给则自动创建 |
| PV 的生命周期？ | Provisioning → Available（未绑）→ Bound（已绑）→ Released（PVC 删了但 PV 保留数据）→ 根据 reclaimPolicy 决定保留/删除/回收 |
| StorageClass 是干嘛的？ | 定义存储类型 + 后端 Provisioner，让用户不用手动创建 PV，创建 PVC 即自动供给 |
| StatefulSet 和 Deployment 区别？ | StatefulSet 每个 Pod 有固定编号（0,1,2…）+ 独立 PVC，扩缩按顺序进行，适合 DB/ES/Kafka |

---

## 四、待补模块三：Ingress 网络管理

### 4.1 面试场景

> "你们的集群外部流量怎么进来的？"
> "Ingress 和 LoadBalancer Service 的区别？"
> "TLS 证书是怎么管理的？"
> "怎么做灰度流量切分？"

### 4.2 核心知识点

| 知识点 | 说明 |
|--------|------|
| **Ingress Controller** | Ingress 规则的实际执行者（nginx-ingress, traefik, kong 等） |
| **Ingress Resource** | 声明式路由规则（域名→路径→Service） |
| **TLS (cert-manager)** | 自动签发/续期 Let's Encrypt 证书 |
| **IngressClass** | 多 Ingress Controller 共存时的路由分流 |
| **Gateway API** | Ingress 的下一代标准（更强大的流量控制） |
| **Annotations** | nginx-ingress 通过 annotation 实现限流/白名单/CORS/重写等 |

### 4.3 流量走向（全链路）

```text
Internet → NodePort/LoadBalancer → Ingress Controller Pod
  → 匹配 Host header (域名)
    → 匹配 path (/api/*, /web/*)
      → 匹配 TLS (证书解密)
        → 转发到 Service → Pod
```

### 4.4 落地目标

```
在你的集群上：
  1. 确认 nginx-ingress Controller 已部署（大概率已装）
  2. 创建 Ingress 规则：tomcat.example.com → tomcat-service:8080
  3. 配置 TLS（自签或沿用已有证书）
  4. 验证外部访问 + curl -k https://tomcat.example.com
  5. 尝试 annotation 限流：nginx.ingress.kubernetes.io/rate-limiting
```

### 4.5 面试速答模板

| 问题 | 一句话 |
|------|--------|
| Ingress 解决了什么问题？ | 用一条规则集中管理多个域名的路由和 TLS，替代每个 Service 单独暴露 LoadBalancer 的浪费 |
| Ingress 和 Service(LoadBalancer) 区别？ | Service LB 每个服务一个公网 IP（贵+散），Ingress 一个入口统一分发（省+集中管理） |
| nginx-ingress 怎么工作的？ | 监听 K8s API 的 Ingress 变更 → 动态渲染 nginx.conf → reload nginx |
| TLS 怎么配？ | 创建 TLS Secret（cert+key）→ Ingress 引用 secretName → Controller 自动启用 HTTPS |
| 怎么做灰度？ | 通过 canary annotation 按权重/Header/Cookie 分流，或直接用 Argo Rollouts 的 TrafficManagement |

---

## 五、三模块优先级 & 实操预估

| 优先级 | 模块 | 复杂度 | 实操预估 | 集群依赖 |
|:------:|------|:------:|----------|----------|
| **P0** | HPA 弹性伸缩 | ⭐⭐ | ~30min | Metrics Server（可能需装） |
| **P1** | PV/PVC 存储 | ⭐⭐⭐ | ~45min | NFS Provisioner |
| **P2** | Ingress 网络 | ⭐⭐ | ~20min | nginx-ingress（集群大概率已有） |

> **建议顺序**：HPA → Ingress → 存储。HPA 面试频率最高且最简单，Ingress 你的集群大概率已有只差配置演示，存储复杂度中等放在最后。

---

## 六、下次如何接续

**工作区路径不变**：`f:/项目管理2026`

**接续方式**：打开 CodeBuddy，在当前工作区直接告诉我：

> "开始补 K8s 三基石，先做 HPA 弹性伸缩"

或者更具体：

> "帮我在集群上给 tomcat-app 配置 HPA，基于 CPU 自动扩缩"
> "搭一个 NFS StorageClass + PVC 示例"
> "给 tomcat-app 配 Ingress 路由和 TLS"

我会读取本文档自动衔接上下文。

---

## 七、项目全景（三基石补完后）

```
✅ CI/CD 三方案        → Jenkins / GitLab CI / ArgoCD
✅ 灰度发布            → Argo Rollouts (Canary / BlueGreen)
✅ 可观测性            → Prometheus + Grafana + Loki + Skywalking（已停服省资源）
✅ 镜像仓库+扫描       → Harbor + Trivy
✅ 多环境+配置管理     → Kustomize overlays
✅ 密钥管理（理论）    → Sealed Secrets
✅ 私有化部署          → HiAgent 实战
✅ HPA 弹性伸缩        → tomcat-app-hpa，CPU 50%，1~5 副本，Metrics Server
✅ PV/PVC 存储         → NFS(h1) → PV(5Gi,RWX) → PVC → Pod，删 Pod 数据不丢
✅ Ingress 网络管理    → tomcat.test → ingress-nginx → Service，路由/限流
```

**DevOps/SRE 面试核心技术栈已全部闭环。**

### 实际落地记录 (2026-07-03)

```text
HPA:
  资源: tomcat-app-hpa (tomcat-dev)
  策略: CPU 50%, min=1, max=5, 当前 2~3% → 1 副本
  验证: kubectl get hpa -n tomcat-dev

存储:
  架构: h1 NFS Server → /srv/nfs-k8s → PV nfs-pv-5gi → PVC tomcat-logs-pvc
  验证: storage-demo Pod 写 /data/persist.log → 删 Pod 重建 → 数据完好
  NFS Server: 192.168.1.61 (h1/harbor)
  注: nfs-subdir-external-provisioner 镜像因 GFW 未拉取，使用静态 PV/PVC

Ingress:
  资源: tomcat-app-ingress (tomcat-dev), Class=nginx
  域名: tomcat.test → 192.168.1.55:80 (NodePort 31716)
  验证: curl -H 'Host: tomcat.test' http://192.168.1.55:31716/health
```

---

## 八、速记卡（三模块面试精华）

| 问题 | 一句话 |
|------|--------|
| HPA 扩容公式？ | desiredReplicas = ceil( currentMetricValue / targetMetricValue × currentReplicas ) |
| HPA 数据来源？ | Metrics Server（默认）+ Prometheus Adapter（自定义指标） |
| PV 绑定条件？ | 容量 >= 请求 + 访问模式匹配 + StorageClass 相同 |
| 动态供给谁触发的？ | PVC 创建时找不到匹配的 PV，StorageClass 的 Provisioner 自动建 |
| Ingress vs LoadBalancer 怎么选？ | 多服务 → Ingress 统一入口；单服务暴露 UDP → LoadBalancer |
| ingress-nginx 限流？ | `nginx.ingress.kubernetes.io/limit-connections`、`limit-rps` annotation |

---

## 九、补充说明

- **监控栈已停服**：master 节点内存 80~87%，仅 worker1/2 有余量，无法承载全量监控（21 Pod, ~6-8Gi）。配置文档和备份快照完整保留，面试讲述架构即可。
- **NFS Provisioner 镜像**：因 GFW 限制未拉取，当前使用静态 PV/PVC 完成存储全链路演示。
- **t1 测试机关闭**：内存不足，不影响集群运行。
