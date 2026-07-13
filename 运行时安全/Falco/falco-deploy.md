# Falco（运行时安全检测） 运行时安全（第 22 项）

> 拼齐 DevSecOps 三层：Trivy 镜像扫描 + Kyverno（策略即代码引擎） 准入控制 + **Falco 运行时检测**。
> 在集群内网、节点无外网、聚焦模式下部署 Falco 0.44.1（DaemonSet，仅 worker 运行）。

## 架构与约束

- **Falco** 以 DaemonSet（守护进程集） 跑在每个节点，用 eBPF 在内核捕获 syscall，匹配规则产生安全告警（stdout / 可接 falcosidekick 转发）。
- 集群内网无外网 → 镜像必须走 `外网资源同步/sync_from_us.ps1` 进 Harbor（私有镜像仓库）；YAML 里 image 写 Harbor 地址；kubelet 自动从 Harbor 拉。
- **必须挡在 master 外**：master 内存红线扛不住；利用 master 默认 `NoSchedule` 污点，把 `tolerations` 置空即可（官方 chart 默认竟容忍 master，需覆盖）。
- **聚焦模式**：全家桶已 scale 0，仅控制面 + Cilium（基于 eBPF 的 CNI/网络方案） + MinIO 在跑；Falco 落在 worker 即可。

## 镜像获取

```powershell
cd 项目实战\外网资源同步
pwsh -ExecutionPolicy Bypass -File .\sync_from_us.ps1 -Image "falcosecurity/falco:0.44.1" -HarborProject "falcosecurity"
# => 192.168.1.61/falcosecurity/falco:0.44.1
```

> 只需同步这 **1 个镜像**。modern_ebpf 不渲染 driver-loader init 容器；容器插件 `libcontainer.so` 已内置在 falco 镜像内；规则用镜像内置版本，不依赖 falcoctl 联网。

## 部署步骤

1. Windows 装 helm、拉官方 chart（走代理），并解析子 chart 依赖：
   ```powershell
   helm repo add falcosecurity https://falcosecurity.github.io/charts
   helm pull falcosecurity/falco --untar --destination C:/tmp/falco-chart
   cd C:/tmp/falco-chart/falco; helm dependency build
   ```
2. 将 `C:/tmp/falco-chart` 与 `falco-values.yaml` scp 到 m1 `/tmp/`。
3. m1 上执行 `deploy-falco.sh`（建 `falco` 命名空间 + `helm install`）。

## 关键配置（falco-values.yaml，离线适配）

- `driver.kind: modern_ebpf`：内核 5.15 支持 CO-RE，免内核模块构建；且不渲染 driver-loader init 容器。
- `image.registry/repository/tag` → `192.168.1.61/falcosecurity/falco:0.44.1`。
- `tolerations: []`：去掉官方默认对 master/control-plane 的容忍，DaemonSet 只落到 worker。
- `collectors.enabled: false` + **手动**在 `falco.plugins` 给 container 插件写 `library_path: libcontainer.so`，并手动挂载 `/run/containerd/containerd.sock`：见下方「踩坑」。
- `falcoctl.artifact.install/follow.enabled: false`：避免 init/sidecar 联网 docker.io 拉规则。

## 踩坑记录（重要，离线部署必看）

1. **插件重复注册**：falco 镜像内置 `/etc/falco/config.d/falco.container_plugin.yaml`，内容 `load_plugins: [container]`。
   - 若用 chart 的 `collectors.containerEngine.enabled: true`，helper 会再往 falco.yaml 塞一份 `load_plugins`+`plugins` → 与 config.d 冲突报 `found another plugin with name container`。
   - 若直接关 `collectors`，falco.yaml 的 `plugins:` 为空，config.d 的 `load_plugins:[container]` 找不到 library_path → 报 `plugin config not found`。
   - **正确做法**：关 `collectors`，仅在 `falco.plugins` 手动给出 container 插件的 `library_path` 配置（load_plugins 交给内置 config.d，单份注册）。
2. **container 插件 engines schema**：`init_config.engines` 要求 **docker/podman/containerd/cri/lxc/libvirt_lxc/bpm 共 7 个键全部存在**，少一个报 `Missing required property 'bpm'`。需补全全部键（enabled 与否都行），并把 containerd/cri 的 sockets 指向本集群的 `/run/containerd/containerd.sock`。
3. **falcoctl 误开**：重写覆盖值时若漏掉 `falcoctl.artifact.install/follow.enabled: false`，会渲染 init 容器去拉 `docker.io/falcosecurity/falcoctl:0.13.0` → `ImagePullBackOff`。离线必须关。

## 验证（运行时检测闭环）

```bash
# 在 demo pod 内触发敏感读取
kubectl -n reliability-demo exec <demo-pod> -- sh -c 'cat /etc/shadow'
# 看 Falco 告警
kubectl -n falco logs -l app.kubernetes.io/instance=falco --tail=40
```

实测告警（节选）：
```
Warning Sensitive file opened for reading by non-trusted program
  file=/etc/shadow ...
  container_name=app
  container_image_repository=192.168.1.61/library/nginx
  container_image_tag=1.25-alpine
  k8s_pod_name=demo-app-6cbdcd8d94-2vbkz
  k8s_ns_name=reliability-demo
```
→ 容器级富化（container_name / 镜像 / pod / ns）离线正常，DevSecOps 三层闭环打通。

## 资源

- 每节点 1 个 Pod（容器组），request 256Mi / limit 512Mi，cpu 100m/500m。
- 仅 worker 运行（2 Pod），master 不受影响。
- 卸载：`helm -n falco uninstall falco`（保留命名空间 `falco`）。
