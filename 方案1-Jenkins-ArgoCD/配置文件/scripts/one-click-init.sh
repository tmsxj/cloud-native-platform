#!/bin/bash
# ============================================================================
# 一键初始化脚本: Jenkins + ArgoCD GitOps 全链路部署
# ============================================================================
# 功能: 从零搭建 CI/CD 环境的参考脚本
# 注意: 实际部署时建议分阶段手动执行，此脚本仅作为流程参考
# 用法: chmod +x one-click-init.sh && ./one-click-init.sh
#
# 环境要求:
#   - kubectl 已配置集群访问
#   - 机器可访问 GitHub（安装 ArgoCD）或已提前下载好 install.yaml
#   - Harbor 镜像仓库已就绪
#   - 各配置文件已在当前目录下
# ============================================================================

set -e   # ← 任何命令失败立即退出

# ---- 加载统一环境配置 ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../../../部署工具/env.sh"
HELPER_FILE="$SCRIPT_DIR/../../../部署工具/deploy-helper.sh"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "❌ 未找到 env.sh，请先复制 env.sh 为 env.local.sh 并填写配置"
    echo "   路径: 项目实战/部署工具/env.sh"
    exit 1
fi
[ -f "$HELPER_FILE" ] && source "$HELPER_FILE"

# ---- 运行时校验 ----
[ "$HARBOR_PASS" = "your-harbor-password" ] && echo "⚠ 警告: 请修改 env.sh 中的 HARBOR_PASS" && exit 1

# ---- envsubst 封装: 自动替换 YAML 模板中的 ${VAR} 后 apply ----
apply_template() {
    local yaml="$1"
    local name=$(basename "$yaml")
    echo "  → 部署: $name (envsubst 模板渲染)"
    envsubst < "$yaml" | kubectl apply -f -
}

echo "=========================================="
echo "  Jenkins + ArgoCD GitOps — 一键部署"
echo "=========================================="

# =====================================================================
# Phase 1: 创建命名空间
# =====================================================================
echo ""
echo "=== Phase 1: 创建命名空间 ==="
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace argocd     --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace jenkins    --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace git        --dry-run=client -o yaml | kubectl apply -f -
echo "✓ 所有命名空间已就绪"

# =====================================================================
# Phase 2: 部署 Git Server（内网 Git 仓库）
# =====================================================================
echo ""
echo "=== Phase 2: 部署 Git Server ==="
apply_template "$SCRIPT_DIR/../git-server/git-server-deployment.yaml"
kubectl wait --for=condition=complete job/git-init -n git --timeout=60s
kubectl wait --for=condition=ready pod -l app=git-server -n git --timeout=120s
echo "✓ Git Server 已就绪"

# =====================================================================
# Phase 3: 部署 ArgoCD
# =====================================================================
echo ""
echo "=== Phase 3: 部署 ArgoCD ==="
# 如果内网无法访问 GitHub，需要提前下载 install.yaml 并导入到本地
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
echo "✓ ArgoCD 已就绪"

# ---- 获取并显示 ArgoCD 初始密码 ----
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "  ArgoCD 初始密码: ${ARGOCD_PASSWORD}"

# =====================================================================
# Phase 4: 创建 imagePullSecrets（Harbor 镜像拉取凭证）
# =====================================================================
echo ""
echo "=== Phase 4: 创建 imagePullSecrets ==="
kubectl create secret docker-registry harbor-regcred \
  -n monitoring \
  --docker-server="${HARBOR_IP}" \
  --docker-username="${HARBOR_USER}" \
  --docker-password="${HARBOR_PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✓ Harbor 镜像拉取凭证已创建"

# =====================================================================
# Phase 5: 注册 Git 仓库到 ArgoCD
# =====================================================================
echo ""
echo "=== Phase 5: 注册 Git 仓库到 ArgoCD ==="
apply_template "$SCRIPT_DIR/../argocd/repo-secret.yaml"
echo "✓ Git 仓库已注册到 ArgoCD"

# =====================================================================
# Phase 6: 创建 ArgoCD Application
# =====================================================================
echo ""
echo "=== Phase 6: 创建 ArgoCD Application ==="
echo "  请手动修改以下文件中的 repoURL 指向你的 Git Server："
echo "    - snownlp-observability-demo/argocd/snownlp-demo-app.yaml"
echo "    - monitoring-config/argocd/application.yaml"
echo ""
echo "  然后执行："
echo "    kubectl apply -f snownlp-observability-demo/argocd/snownlp-demo-app.yaml"
echo "    kubectl apply -f monitoring-config/argocd/application.yaml"

# =====================================================================
# Phase 7: 部署 Jenkins
# =====================================================================
echo ""
echo "=== Phase 7: 部署 Jenkins ==="
apply_template "$SCRIPT_DIR/../jenkins/jenkins-deploy.yaml"
kubectl wait --for=condition=ready pod -l app=jenkins -n jenkins --timeout=300s
echo "✓ Jenkins 已就绪"

echo ""
echo "=========================================="
echo "  一键部署完成！"
echo "=========================================="
echo "  Jenkins : http://${JENKINS_URL}"
echo "  ArgoCD  : http://${ARGOCD_URL}"
echo "  ArgoCD 密码: ${ARGOCD_PASSWORD}"
echo "  Grafana  : http://${GRAFANA_URL}"
echo "  Demo API : http://snownlp.lab.local:${NODE_PORT}/docs"
echo ""
echo "  接下来请手动："
echo "  1. 通过 API 创建 Jenkins Pipeline Job（参考 jenkins-job-config.xml）"
echo "  2. 修改并应用 ArgoCD Application YAML"
echo "  3. 推送代码到 Git Server"
echo "=========================================="
