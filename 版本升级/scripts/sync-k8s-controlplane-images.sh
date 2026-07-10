#!/bin/bash
# 同步 K8s 控制面镜像到 Harbor 的 registry.k8s.io 项目（离线升级用）
# 链路: H1(harbor) --(keyless ssh)--> US(usimage) docker pull/save --> scp 回 H1 --> load/tag/push Harbor
# 用法: 在 H1 上以能 keyless ssh 到 US 的用户执行
# 重要: 镜像必须落 Harbor 的 registry.k8s.io 项目并保持原始子路径，
#        与集群 kubeadm-config 的 imageRepository(192.168.1.61/registry.k8s.io) 一致。
set -e
HARBOR=192.168.1.61
PROJECT=registry.k8s.io
US=usimage
K8S_VER=v1.29.15
ETCD=3.5.16-0
COREDNS=v1.11.1
PAUSE=3.9
IMAGES=(
  "kube-apiserver:${K8S_VER}"
  "kube-controller-manager:${K8S_VER}"
  "kube-scheduler:${K8S_VER}"
  "kube-proxy:${K8S_VER}"
  "etcd:${ETCD}"
  "coredns/coredns:${COREDNS}"
  "pause:${PAUSE}"
)
for img in "${IMAGES[@]}"; do
  safe=$(echo "$img" | tr '/:' '__')
  echo "=== $img ==="
  ssh "$US" "docker pull registry.k8s.io/$img && docker save registry.k8s.io/$img -o /tmp/k8s_${safe}.tar"
  scp "$US:/tmp/k8s_${safe}.tar" "/tmp/k8s_${safe}.tar"
  docker load -i "/tmp/k8s_${safe}.tar"
  docker tag "registry.k8s.io/$img" "${HARBOR}/${PROJECT}/$img"
  docker push "${HARBOR}/${PROJECT}/$img"
done
echo "SYNC_REGISTRY_K8SIO_DONE"
