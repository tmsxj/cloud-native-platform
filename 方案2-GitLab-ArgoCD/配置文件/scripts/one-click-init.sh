#!/bin/bash
# =============================================================================
# GitLab + ArgoCD 一键初始化脚本 (参考版)
# =============================================================================
# 用途: 从零搭建 GitLab + ArgoCD GitOps 全链路
# 使用: bash one-click-init.sh
# 注意: 分阶段手动执行更为稳妥，本脚本仅供快速参考
# =============================================================================

set -e

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

echo "============================================"
echo " GitLab + ArgoCD GitOps 一键初始化"
echo "============================================"

# ---- 阶段 1: 部署 GitLab ----
echo ""
echo ">>> 阶段 1: 部署 GitLab"
apply_template "$SCRIPT_DIR/../gitlab/gitlab-deploy.yaml"

echo "等待 GitLab Pod 就绪 (可能需要 3-5 分钟)..."
kubectl wait --for=condition=ready pod -l app=gitlab -n $GITLAB_NS --timeout=600s

echo "获取 GitLab 初始密码..."
GITLAB_ROOT_PASS=$(kubectl exec -n $GITLAB_NS deployment/gitlab -- \
  cat /etc/gitlab/initial_root_password 2>/dev/null | grep "^Password:" | awk '{print $2}')

if [ -z "$GITLAB_ROOT_PASS" ]; then
  echo "密码未就绪，请稍后执行:"
  echo "  kubectl exec -n $GITLAB_NS deployment/gitlab -- cat /etc/gitlab/initial_root_password"
else
  echo "GitLab Root 密码: $GITLAB_ROOT_PASS"
fi

# ---- 阶段 2: 准备 Harbor 镜像 ----
echo ""
echo ">>> 阶段 2: 准备 Harbor 基础镜像"
docker login $HARBOR_IP -u $HARBOR_USER -p $HARBOR_PASS

# 准备 GitLab CE 和 Runner 镜像
for IMG in \
  "maven:3.8-openjdk-11-slim" \
  "tomcat:9.0-jdk11-openjdk-slim" \
  "alpine:latest" \
  "docker:24-cli" \
  "alpine/git:latest"
do
  echo "准备镜像: $HARBOR_IP/library/$IMG"
  docker pull "$IMG" || echo "  (跳过拉取失败，可能已存在)"
  docker tag "$IMG" "$HARBOR_IP/library/$IMG" 2>/dev/null || true
  docker push "$HARBOR_IP/library/$IMG" 2>/dev/null || echo "  (跳过推送，可能已存在)"
done

# ---- 阶段 3: 创建 Harbor 项目 ----
echo ""
echo ">>> 阶段 3: 创建 Harbor 项目"
curl -u "$HARBOR_USER:$HARBOR_PASS" -X POST \
  "http://$HARBOR_IP/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -d "{\"project_name\":\"tomcat-demo\",\"public\":true}" 2>/dev/null || echo "项目可能已存在"

# ---- 阶段 4: 部署 GitLab Runner ----
echo ""
echo ">>> 阶段 4: 部署 GitLab Runner"
echo "注意: 部署前请替换 gitlab-runner-secret 中的 registration-token"
echo "获取方式: GitLab Admin → CI/CD → Runners → New instance runner"
read -p "已完成 Token 替换? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  apply_template "$SCRIPT_DIR/../gitlab/gitlab-runner-deploy.yaml"
fi

# ---- 阶段 5: 创建 tomcat-demo 命名空间和 Secret ----
echo ""
echo ">>> 阶段 5: 创建 tomcat-demo 命名空间"
kubectl create namespace $TOMCAT_NS --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry harbor-regcred \
  --namespace $TOMCAT_NS \
  --docker-server=$HARBOR_IP \
  --docker-username=$HARBOR_USER \
  --docker-password=$HARBOR_PASS \
  --dry-run=client -o yaml | kubectl apply -f -

# ---- 阶段 6: 注册 ArgoCD 仓库 ----
echo ""
echo ">>> 阶段 6: 注册 GitLab 仓库到 ArgoCD"
ARGOCD_PASS=$(kubectl -n $ARGOCD_NS get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")

if [ -z "$ARGOCD_PASS" ]; then
  echo "无法自动获取 ArgoCD 密码，请手动注册:"
  echo "  argocd repo add http://gitlab.gitlab.svc.cluster.local/root/tomcat-app.git --insecure --grpc-web"
else
  argocd login ${ARGOCD_URL} --username admin --password "$ARGOCD_PASS" --insecure --grpc-web 2>/dev/null || true
  argocd repo add "http://gitlab.gitlab.svc.cluster.local/root/tomcat-app.git" --insecure --grpc-web 2>/dev/null || echo "仓库可能已注册"
fi

# ---- 阶段 7: 创建 ArgoCD Application ----
echo ""
echo ">>> 阶段 7: 创建 ArgoCD Application"
apply_template "$SCRIPT_DIR/../argocd/tomcat-app.yaml"

# ---- 完成 ----
echo ""
echo "============================================"
echo " 初始化完成!"
echo "============================================"
echo "下一步:"
echo "  1. 在 GitLab 创建项目 tomcat-app"
echo "  2. 推送代码: git push origin main"
echo "  3. 在 GitLab 设置 CI Variables"
echo "  4. 查看 ArgoCD 同步状态"
echo "============================================"
