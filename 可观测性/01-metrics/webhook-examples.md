# 即时通讯告警集成：飞书 + 企业微信 Webhook

> **状态**: 配置案例 —— 不做实操部署，但提供可直接套用的模板  
> **中转方案**: prometheus-webhook-dingtalk（适配钉钉/飞书/企微的通用 webhook 翻译器）

---

## 原理

```
AlertManager → POST /webhook → prometheus-webhook-dingtalk → 飞书/企微 API
                                    ↑
                               把 AlertManager 标准 JSON
                               翻译成各 IM 平台的消息格式
```

AlertManager 原生不支持飞书/企微的消息体格式，中间需要一个翻译层。

---

## 一、部署 prometheus-webhook-dingtalk

```bash
# 部署为 Deployment，暴露 ClusterIP Service
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webhook-dingtalk
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webhook-dingtalk
  template:
    metadata:
      labels:
        app: webhook-dingtalk
    spec:
      containers:
        - name: webhook-dingtalk
          image: timonwong/prometheus-webhook-dingtalk:latest
          args:
            - --web.listen-address=:8060
            # 飞书模板文件（可选，如果用默认模板可省略）
            - --ding.profile=feishu=https://open.feishu.cn/open-apis/bot/v2/hook/<YOUR_TOKEN>
            # 企微模板文件
            - --ding.profile=wecom=https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=<YOUR_KEY>
          ports:
            - containerPort: 8060
              name: http
---
apiVersion: v1
kind: Service
metadata:
  name: webhook-dingtalk
  namespace: monitoring
spec:
  selector:
    app: webhook-dingtalk
  ports:
    - port: 8060
      targetPort: 8060
EOF
```

---

## 二、飞书（Lark / Feishu）配置

### 2.1 获取飞书 Webhook 地址

1. 飞书客户端 → 群聊设置 → 群机器人 → 添加自定义机器人
2. 复制 Webhook 地址，格式如下：

```
https://open.feishu.cn/open-apis/bot/v2/hook/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

### 2.2 AlertManager 路由配置

```yaml
# alertmanager.yml 中新增飞书 receiver
route:
  receiver: email-default
  routes:
    - match:
        severity: critical
      receiver: feishu-critical    # critical 走飞书
      continue: true                # 同时保留邮件通知
    - match:
        severity: warning
      receiver: feishu-warning

receivers:
  # ---- 飞书 critical ----
  - name: feishu-critical
    webhook_configs:
      - url: http://webhook-dingtalk.monitoring:8060/dingtalk/feishu/send
        send_resolved: true
        http_config:
          follow_redirects: true

  # ---- 飞书 warning ----
  - name: feishu-warning
    webhook_configs:
      - url: http://webhook-dingtalk.monitoring:8060/dingtalk/feishu/send
        send_resolved: true
```

> **关键点**: URL 中的 `/feishu` 对应 `--ding.profile=feishu=...` 的 profile 名

### 2.3 飞书消息效果预览

```
🔴 [CRITICAL] NodeCPUExhausted
节点: worker1 (192.168.1.62)
描述: worker1 CPU 使用率 > 95% 持续 5 分钟
当前值: 97.3%
触发时间: 2026-06-24 10:15:30

🔗 Prometheus → http://prometheus.lab.local:31716
```

### 2.4 飞书特有的安全配置（可选）

如果在飞书机器人设置中开启了"签名校验"：

```yaml
# webhook-dingtalk 启动参数需额外传入
args:
  - --web.listen-address=:8060
  - --ding.profile=feishu=https://open.feishu.cn/open-apis/bot/v2/hook/xxx?secret=<SIGN_SECRET>
```

或者用飞书官方推荐的 HMAC-SHA256 签名方式（需在 webhook-dingtalk 配置模板中声明）。

---

## 三、企业微信（WeCom）配置

### 3.1 获取企微 Webhook 地址

1. 企业微信管理后台 → 应用管理 → 群机器人 → 新建机器人
2. 复制 Webhook 地址，格式如下：

```
https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

### 3.2 AlertManager 路由配置

```yaml
receivers:
  # ---- 企微 critical ----
  - name: wecom-critical
    webhook_configs:
      - url: http://webhook-dingtalk.monitoring:8060/dingtalk/wecom/send
        send_resolved: true

  # ---- 企微 warning ----
  - name: wecom-warning
    webhook_configs:
      - url: http://webhook-dingtalk.monitoring:8060/dingtalk/wecom/send
        send_resolved: true
```

### 3.3 企微消息效果预览

```
🔴 [CRITICAL] 节点 CPU 耗尽
节点: worker1
CPU 使用率: 97.3%（阈值: 95%）
持续时间: 5分钟
发生时间: 2026-06-24 10:15:30
```

### 3.4 企微 vs 飞书对比

| 维度 | 飞书 | 企业微信 |
|------|------|---------|
| Webhook URL | `open.feishu.cn/open-apis/bot/v2/hook/{token}` | `qyapi.weixin.qq.com/cgi-bin/webhook/send?key={key}` |
| 签名校验 | 可选（推荐开启） | 默认无 |
| 消息格式 | 富文本卡片（更丰富） | Markdown（简洁） |
| 群聊 @人 | 支持 | 支持 |
| 单条大小限制 | 30KB | 20KB |
| 适用场景 | 互联网/科技公司 | 传统企业/制造/政府 |

---

## 四、三级通知通道策略（最佳实践）

实际生产环境中，不同级别走不同通道：

```
severity=critical
  ├─ 飞书/企微群 @所有人      ← 必须立刻有人处理
  ├─ 邮件 【CRITICAL】          ← 书面留痕
  └─ 短信/电话（PagerDuty）    ← 极端情况

severity=warning
  ├─ 飞书/企微群（不 @人）     ← 通知但不骚扰
  └─ 邮件 【WARNING】

severity=info / watchdog
  └─ 不发                        ← 避免告警疲劳
```

### 最终 AlertManager 路由树

```yaml
route:
  receiver: email-default
  group_by: [alertname, namespace]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h

  routes:
    # critical: 飞书 + 邮件双通道
    - match:
        severity: critical
      receiver: feishu-critical
      continue: true       # 继续往下匹配，让邮件也收到
    - match:
        severity: critical
      receiver: email-critical

    # warning: 只走企微（不骚扰邮件）
    - match:
        severity: warning
      receiver: wecom-warning

    # watchdog: 不发通知（纯心跳检测用）
    - match:
        alertname: Watchdog
      receiver: 'null'

receivers:
  - name: feishu-critical
    webhook_configs:
      - url: http://webhook-dingtalk.monitoring:8060/dingtalk/feishu/send
        send_resolved: true
  - name: wecom-warning
    webhook_configs:
      - url: http://webhook-dingtalk.monitoring:8060/dingtalk/wecom/send
        send_resolved: true
  - name: email-critical
    email_configs:
      - to: tmsxj@foxmail.com
        headers:
          Subject: '[CRITICAL] {{ .GroupLabels.alertname }}'
  - name: 'null'
```

---

## 五、面试讲法

> "告警通知我配了两级通道——critical 走飞书群 @所有人 + 邮件留痕，warning 走企微群不 @人，抑制规则避免了告警风暴。中间用 prometheus-webhook-dingtalk 做翻译层，把 AlertManager 的标准 JSON 转成飞书/企微的消息卡片格式。URL 的 `/feishu` 和 `/wecom` 路径对应不同的群机器人 token，一个 deployment 同时服务两个通道。"
