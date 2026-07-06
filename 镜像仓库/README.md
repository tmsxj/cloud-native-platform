# P1.9 — Harbor 自动清理策略

> 📅 2026-07-06 完成 | 验证状态: ✅ Retention Policy + GC Schedule 已配置

## 做了什么

1. 通过 Harbor API 设置 Retention Policy（监控项目保留最新 10 个 tag）
2. 配置 GC Schedule（每日凌晨 3:00 自动清理）
3. 避免镜像无限制增长撑满磁盘

## Retention Policy

```json
{
  "algorithm": "or",
  "rules": [
    {
      "action": "retain",
      "template": "always",
      "scope_selectors": {
        "repository": [{ "pattern": "**", "decoration": "repoMatches" }]
      }
    },
    {
      "action": "retain",
      "template": "latestPushedK",
      "params": { "latestPushedK": 10 },
      "scope_selectors": {
        "repository": [{ "pattern": "**", "decoration": "repoMatches" }]
      }
    }
  ],
  "trigger": { "kind": "Schedule", "settings": { "cron": "0 3 * * *" } },
  "scope": { "level": "project", "ref": "monitoring" }
}
```

## GC Schedule

```bash
# 设置每日凌晨 3:00 自动 GC
curl -X PUT "http://harbor.lab.local/api/v2.0/system/gc/schedule" \
  -H "Authorization: Basic $(echo -n admin:password | base64)" \
  -H "Content-Type: application/json" \
  -d '{"schedule":{"cron":"0 3 * * *","type":"Custom"}}'
```

## 面试要点

1. **Retention vs GC**: Retention 只标记/标记删除，GC 实际释放磁盘空间，两者需配合
2. **Harbor GC 原理**: 标记 → 清理 → 释放 layer（引用计数为零的 blob）
3. **为什么需要策略**: 监控组件镜像频繁更新（Promtail/Node Exporter），不清理会撑满 Harbor 磁盘
4. **生产建议**: 开发环境保留 5-10 tag，生产保留 20-30 tag，按项目粒度配置
