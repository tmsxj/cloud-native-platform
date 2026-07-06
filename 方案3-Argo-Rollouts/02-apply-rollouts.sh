#!/bin/bash
# =============================================================================
# P2: 应用 Rollout 清单到集群
# =============================================================================
# 注意事项:
#   - 当前 GitLab 已关停，无法通过 ArgoCD GitOps 方式部署
#   - 此脚本直接 kubectl apply（临时方案）
#   - 现有 tomcat Deployment 会被 ArgoCD 尝试回滚
#     执行前需先在 ArgoCD 中禁用对应 Application 的 auto-sync
#   - GitLab 恢复后应将 k8s/ 目录提交到 Git 仓库恢复 GitOps
# =============================================================================
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
K8S_DIR="${BASE_DIR}/k8s"
ENV_FILE="${BASE_DIR}/../部署工具/env.sh"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

echo "=========================================="
echo " P2: 部署 Rollout 清单 (kubectl apply)"
echo "=========================================="
echo ""
echo "⚠  提示: ArgoCD 可能会尝试回滚这些变更"
echo "   建议先执行: kubectl patch app tomcat-app-dev -n argocd \\"
echo "              --type=merge -p '{\"spec\":{\"syncPolicy\":{\"automated\":null}}}'"
echo ""

read -rp "是否继续? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "已取消"
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. DEV 环境 - 金丝雀发布
# ---------------------------------------------------------------------------
echo ""
echo "[1/3] 部署 DEV 环境 (金丝雀)..."
kubectl kustomize "${K8S_DIR}/overlays/dev" | envsubst | kubectl apply -f -
echo "  ✓ DEV 已部署"

# ---------------------------------------------------------------------------
# 2. STAGING 环境 - 蓝绿发布
# ---------------------------------------------------------------------------
echo "[2/3] 部署 STAGING 环境 (蓝绿)..."
kubectl kustomize "${K8S_DIR}/overlays/staging" | envsubst | kubectl apply -f -
echo "  ✓ STAGING 已部署"

# ---------------------------------------------------------------------------
# 3. PROD 环境 - 蓝绿发布
# ---------------------------------------------------------------------------
echo "[3/3] 部署 PROD 环境 (蓝绿+手动推进)..."
kubectl kustomize "${K8S_DIR}/overlays/prod" | envsubst | kubectl apply -f -
echo "  ✓ PROD 已部署"

echo ""
echo "=========================================="
echo " 部署完成 - 验证状态"
echo "=========================================="
echo ""
echo "查看所有 Rollout:"
echo "  kubectl argo rollouts list rollout -A"
echo ""
echo "查看 DEV (金丝雀):"
echo "  kubectl argo rollouts get rollout tomcat-app -n tomcat-dev"
echo ""
echo "查看 STAGING (蓝绿):"
echo "  kubectl argo rollouts get rollout tomcat-app -n tomcat-staging"
echo ""
echo "查看 PROD (蓝绿):"
echo "  kubectl argo rollouts get rollout tomcat-app -n tomcat-prod"
echo ""
echo "监听发布状态:"
echo "  kubectl argo rollouts status tomcat-app -n tomcat-dev --watch"
