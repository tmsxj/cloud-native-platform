# K8s（Kubernetes，容器编排引擎） 集群离线版本升级 · 实战演练

> 把一次真实的 **kubeadm 集群离线小版本升级** 完整落地为可复用文档：计划 → 备料 → 升级 → 验证 → 恢复，含每一步踩到的坑与解决（边做边记）。

## 演练目标
- **集群**：kubeadm 部署，5 节点（m1/m2/m3 控制面 + w1/w2 工作节点），containerd 运行时，内核 5.15
- **升级路径**：`v1.28.15 → v1.29.15`（1.29 系列最新补丁，2026-07-10 官方 `stable-1.29` 端点确认）
- **硬约束**：集群无外网。所有镜像 / 二进制经 **US 中继 → Harbor（私有镜像仓库）(192.168.1.61) → 节点**；Windows 宿主机无法直接连 6443，kubectl 全部经 m1 `sudo` 执行

## 为什么做这次升级
1. 双网格对比演练里 **Linkerd（服务网格） edge** 受限于 **K8s 1.28 不允许 init-container 带探针（1.29+ 才放开）**，被迫回退到 stable-2.14.10；升级到 1.29 从根上解除该限制。
2. 把"**离线升级**"本身做成一项实战能力沉淀下来（离线环境是常态，不能依赖 `apt-get upgrade`）。

## 阶段进度
| 阶段 | 内容 | 状态 |
|---|---|---|
| 0 | 情报收集：版本号、US 同步机制、控制面镜像清单 | ✅ |
| 1 | 离线物料备料（kubeadm/kubelet/kubectl 二进制 + 控制面镜像入 Harbor `registry.k8s.io` 项目） | ✅ |
| 2 | 升级前清理（非必要负载 scale 0 + 移除会拦截系统 Pod（容器组） 的 webhook） | ✅ |
| 3 | 控制面升级（m1 → m2 → m3） | ✅ |
| 4 | 工作节点升级（w1 → w2） | ✅ |
| 5 | 验证（节点版本 / 核心组件 / CNI（容器网络接口）） | ✅ |
| 6 | 恢复演示负载（双网格控制面 / 注入 webhook 重建 / demo 注入） | ✅ |
| 7 | 文档定稿 + force-push 远程 main | ✅ |

## 目录
- `01-升级计划.md` — 详细计划、命令清单、与"踩坑后修正"的对拍表
- `02-实操日志.md` — 逐步操作记录 + 踩坑与解决（边做边记）
- `scripts/` — 本次升级用到的脚本（镜像同步 / 节点升级 / 恢复）

## 关键结论（已核实 · 含修正）
- **Harbor 项目是 `registry.k8s.io`，不是 `kubernetes`**。集群 kubeadm-config 的 `imageRepository` 真实值是 `192.168.1.61/registry.k8s.io`；控制面镜像须推到 Harbor 的 **`registry.k8s.io` 项目并保持原始子路径**（如 `registry.k8s.io/coredns/coredns`、`registry.k8s.io/etcd`、`registry.k8s.io/kube-apiserver`）。推到 `kubernetes` 项目会被 kubeadm 报 "not found"。
- **`kubeadm upgrade apply` 不支持 `--image-repository` 标志**（apply 子命令无该 flag，会 `unknown flag`）。镜像仓库取自 kubeadm-config ConfigMap（配置字典） 的 `imageRepository`，要改就 sed 改 ConfigMap（本演练没改，保持原值即可）。
- **kubeadm v1.29 的 `upgrade node` 已移除 `--control-plane` 标志**。它自动检测本节点是否为控制面并升级静态 Pod（phases 含 `control-plane`/`kubelet-config`），工作节点则自动跳过控制面阶段。带 `--control-plane` 会 `unknown flag`。
- **致命坑（务必记牢）**：用 `cp /tmp/kubelet /usr/bin/kubelet` 覆盖时，若源文件无执行位（`-rw-r--r--`），目标会**丢失 x 位** → systemd 无法 exec kubelet（`status=203/EXEC`、`Failed to locate executable /usr/bin/kubelet: Permission denied`），kubelet 崩溃重启循环；此时 `kubeadm upgrade node` 写的新 etcd 清单**无人接管**，静态 Pod hash 始终不变 → etcd 阶段 5 分钟超时**回滚**。**必须在 cp 之后 `chmod 755` 三个二进制**。
- **节点间无互信 SSH**：m1 不能直连其他节点。二进制经 **Windows 宿主机作中继**（ssh 别名 `m1~m3/w1/w2` 可用，裸 IP 会挂起超时）→ scp 到各节点 `/tmp`，再 `sudo bash` 执行。
- **PowerShell Core 下的两个坑**：① 仓库里的 `sync_from_us.ps1` 把 bash 写在 here-string 里，被 PowerShell Core 当 PS 语法解析报 ParserError（脚本是给 5.1 写的）→ 改用 `H1 → US` 的等价 bash 流程；② ssh 命令串里**内层双引号**（如 `grep -E "a|b"`）会截断外层字符串 → 一律**写脚本文件 + scp 到目标 + `sudo bash 脚本` 执行**，绕开所有引号/转义问题。
- CNI **Cilium v1.17.6**、Kyverno（策略即代码引擎） v1.18.1、Istio 1.30.2、Linkerd 2.14.10、Falco 0.44.1 均兼容 1.29；升级全程这些插件未动。
- **升级前删除的注入 webhook 不会自动重建**：`istio-sidecar-injector` / `linkerd-proxy-injector` 被删后，istiod / linkerd-proxy-injector 不会自己重建（它们只 patch 已有配置）。升级后需用**原安装清单**重放重建——Istio（服务网格） 用当时生成的 `istio-final.yaml`（`kubectl apply -f` 幂等），Linkerd 从 `linkerd-control-plane.yaml` 抽取 `MutatingWebhookConfiguration` 段重放。
- 最终：`kubectl get nodes` 5 节点全 `v1.29.15` Ready；kube-system 核心 Pod（etcd/apiserver/controller/scheduler/coredns/kube-proxy）全 Running；双网格 demo 注入恢复 2/2。
