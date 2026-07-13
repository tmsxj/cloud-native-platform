# P1.9 — Harbor（私有镜像仓库） 自动清理策略

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

## 镜像仓库选型对比

| 维度 | Harbor（本项目采用） | Docker Registry（原生） | Nexus | Zot |
|------|---------------------|------------------------|-------|-----|
| 图形界面 | ✅ 完整 UI | ❌ 无 | ✅ | ❌ |
| 权限/项目 | 项目级 RBAC（基于角色的访问控制） | 弱 | ✅ | 基础 |
| 镜像签名/扫描 | 可接 Trivy/Notary | ❌ | 部分 | ✅ 内建签名 |
| 垃圾回收 | Retention + GC Schedule | 手动 `registry gc` | 支持 | 支持 |
| 适用 | 企业级、需治理 | 极简单节点 | 多格式仓库（maven/npm 等） | 云原生/供应链（OCI 签名） |

> 本项目选 Harbor：图形化 + 项目权限 + 可接 Trivy 扫描与 cosign 签名，闭环 DevSecOps 镜像治理。

## 面试要点

1. **Retention vs GC**: Retention 只标记/标记删除，GC 实际释放磁盘空间，两者需配合
2. **Harbor GC 原理**: 标记 → 清理 → 释放 layer（引用计数为零的 blob）
3. **为什么需要策略**: 监控组件镜像频繁更新（Promtail/Node（节点） Exporter），不清理会撑满 Harbor 磁盘
4. **生产建议**: 开发环境保留 5-10 tag，生产保留 20-30 tag，按项目粒度配置
