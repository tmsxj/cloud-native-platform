#!/bin/bash
# ============================================================================
# Sealed Secrets 镜像搬运脚本
# ============================================================================
# 功能: 将 Sealed Secrets Controller 镜像从 docker.io 搬运到内网 Harbor
#       解决 K8s 集群无法直接访问 docker.io 的问题
#
# 版本选择: 0.27.1 — 与集群中 K8s v1.28 兼容的稳定版本
#   兼容性验证: kubeseal v0.27.1 的 CRD 与 K8s 1.22-1.29 兼容
#
# 前置条件: 当前机器能同时访问 docker.io 和 Harbor
# 用法: source ../../部署工具/env.sh && bash push-image.sh
# ============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../../部署工具/env.sh"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

# ---- 镜像源与目标 ----
# SOURCE: docker.io 官方源 (需要外网访问)
# TARGET: 内网 Harbor 目标地址 (由 env.sh 中的 HARBOR_IP 变量控制)
SOURCE="docker.io/bitnami/sealed-secrets-controller:0.27.1"
TARGET="${HARBOR_IP:-192.168.1.61}/library/sealed-secrets-controller:0.27.1"

# ============================================================================
# Step 1/3: 从 docker.io 拉取镜像
# ============================================================================
echo ">>> [1/3] 拉取镜像: ${SOURCE}"
docker pull ${SOURCE}

# ============================================================================
# Step 2/3: 重新打标签 (Tag 到内网 Harbor)
# ============================================================================
echo ">>> [2/3] 重新打标签: ${TARGET}"
docker tag ${SOURCE} ${TARGET}

# ============================================================================
# Step 3/3: 推送到内网 Harbor
# ============================================================================
echo ">>> [3/3] 推送到 Harbor (请确保已 docker login ${HARBOR_IP:-192.168.1.61})"
docker push ${TARGET}

echo ""
echo "✅ 完成! 镜像已推送到 Harbor"
echo "现在可以部署 Sealed Secrets Controller:"
echo "  kubectl apply -f controller.yaml"
echo ""
echo "部署后验证:"
echo "  kubectl -n kube-system get pods -l name=sealed-secrets-controller"
echo "  kubeseal --fetch-cert --controller-name=sealed-secrets-controller --controller-namespace=kube-system"
