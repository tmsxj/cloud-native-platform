# =============================================================================
# P2: Argo Rollouts 安装脚本 (Windows PowerShell)
# =============================================================================
param(
    [string]$Version = "v1.8.0"
)

$NAMESPACE = "argo-rollouts"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " P2: Argo Rollouts 安装" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# Step 1: 创建命名空间
# ---------------------------------------------------------------------------
Write-Host "[Step 1/3] 创建 argo-rollouts 命名空间..." -ForegroundColor Yellow
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
Write-Host "  ✓ 命名空间已就绪" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 2: 安装 Argo Rollouts Controller
# ---------------------------------------------------------------------------
Write-Host "[Step 2/3] 安装 Argo Rollouts Controller $Version..." -ForegroundColor Yellow
kubectl apply -n $NAMESPACE `
  -f "https://github.com/argoproj/argo-rollouts/releases/download/$Version/install.yaml"
Write-Host "  ✓ Controller 已安装" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 3: 等待 Controller Ready
# ---------------------------------------------------------------------------
Write-Host "[Step 3/3] 等待 Controller Pod 就绪..." -ForegroundColor Yellow
Start-Sleep -Seconds 10
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=argo-rollouts `
  -n $NAMESPACE --timeout=120s 2>$null
if ($LASTEXITCODE -ne 0) {
    kubectl rollout status deployment/argo-rollouts -n $NAMESPACE --timeout=120s
}
Write-Host "  ✓ Controller 已就绪" -ForegroundColor Green

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Argo Rollouts 安装完成" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "验证命令:"
Write-Host "  kubectl get pods -n $NAMESPACE"
Write-Host ""
Write-Host "kubectl 插件请手动安装:"
Write-Host "  https://github.com/argoproj/argo-rollouts/releases/download/$Version/kubectl-argo-rollouts-windows-amd64.exe"
Write-Host ""
Write-Host "下一步: 执行 02-apply-rollouts.sh"
