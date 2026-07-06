#!/bin/bash
# =============================================================================
# P2: Argo Rollouts 安装脚本
# =============================================================================
# 用途: 在 K8s 集群上安装 Argo Rollouts Controller + kubectl 插件
# 所需资源: ~30-50Mi 内存，仅一个 controller pod
# =============================================================================
set -euo pipefail

NAMESPACE="argo-rollouts"
ROLLOUTS_VERSION="v1.8.0"

echo "=========================================="
echo " P2: Argo Rollouts 安装"
echo "=========================================="
echo ""

# ---------------------------------------------------------------------------
# Step 1: 创建命名空间
# ---------------------------------------------------------------------------
echo "[Step 1/4] 创建 argo-rollouts 命名空间..."
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
echo "  ✓ 命名空间已就绪"

# ---------------------------------------------------------------------------
# Step 2: 安装 Argo Rollouts Controller
# ---------------------------------------------------------------------------
echo "[Step 2/4] 安装 Argo Rollouts Controller ${ROLLOUTS_VERSION}..."
kubectl apply -n ${NAMESPACE} \
  -f "https://github.com/argoproj/argo-rollouts/releases/download/${ROLLOUTS_VERSION}/install.yaml"
echo "  ✓ Controller 已安装"

# ---------------------------------------------------------------------------
# Step 3: 等待 Controller Ready
# ---------------------------------------------------------------------------
echo "[Step 3/4] 等待 Controller Pod 就绪..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=argo-rollouts \
  -n ${NAMESPACE} --timeout=120s 2>/dev/null || \
kubectl rollout status deployment/argo-rollouts -n ${NAMESPACE} --timeout=120s
echo "  ✓ Controller 已就绪"

# ---------------------------------------------------------------------------
# Step 4: 安装 kubectl argo rollouts 插件 (Linux/macOS)
# ---------------------------------------------------------------------------
echo "[Step 4/4] 安装 kubectl argo rollouts 插件..."
if command -v curl &> /dev/null; then
  # Linux amd64
  curl -sSL "https://github.com/argoproj/argo-rollouts/releases/download/${ROLLOUTS_VERSION}/kubectl-argo-rollouts-linux-amd64" \
    -o /usr/local/bin/kubectl-argo-rollouts 2>/dev/null && chmod +x /usr/local/bin/kubectl-argo-rollouts && \
    echo "  ✓ kubectl-argo-rollouts 已安装到 /usr/local/bin/" || \
    echo "  ⚠ 请手动安装: https://github.com/argoproj/argo-rollouts/releases"
else
  echo "  ⚠ curl 不可用，请手动安装: https://github.com/argoproj/argo-rollouts/releases"
fi

echo ""
echo "=========================================="
echo " Argo Rollouts 安装完成"
echo "=========================================="
echo ""
echo "验证命令:"
echo "  kubectl get pods -n ${NAMESPACE}"
echo "  kubectl argo rollouts version"
echo ""
echo "下一步: 执行 02-apply-rollouts.sh 部署 Rollout 清单"
