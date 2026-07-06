# =============================================================================
# P2: 应用 Rollout 清单到集群 (Windows PowerShell)
# =============================================================================
param(
    [switch]$Force = $false
)

$BASE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$K8S_DIR = Join-Path $BASE_DIR "k8s"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " P2: 部署 Rollout 清单 (kubectl apply)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "策略说明:" -ForegroundColor Gray
Write-Host "  DEV     → 金丝雀 (20% → 40% → 100%)" -ForegroundColor Gray
Write-Host "  STAGING → 蓝绿   (手动推进)" -ForegroundColor Gray
Write-Host "  PROD    → 蓝绿   (手动推进, 10min 安全窗口)" -ForegroundColor Gray
Write-Host ""

if (-not $Force) {
    Write-Host "⚠  提示: ArgoCD 可能会回滚裸 kubectl apply 的变更" -ForegroundColor DarkYellow
    Write-Host "   建议先执行:" -ForegroundColor DarkYellow
    Write-Host '   kubectl patch app tomcat-app-dev -n argocd --type=merge -p "{\"spec\":{\"syncPolicy\":{\"automated\":null}}}"' -ForegroundColor DarkYellow
    Write-Host '   kubectl patch app tomcat-app-staging -n argocd --type=merge -p "{\"spec\":{\"syncPolicy\":{\"automated\":null}}}"' -ForegroundColor DarkYellow
    Write-Host '   kubectl patch app tomcat-app-prod -n argocd --type=merge -p "{\"spec\":{\"syncPolicy\":{\"automated\":null}}}"' -ForegroundColor DarkYellow
    Write-Host ""

    $confirm = Read-Host "是否继续? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "已取消" -ForegroundColor Red
        exit 0
    }
}

# ---------------------------------------------------------------------------
# 1. DEV 环境 - 金丝雀发布
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "[1/3] 部署 DEV 环境 (金丝雀)..." -ForegroundColor Yellow
kubectl apply -k "$K8S_DIR\overlays\dev"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ✗ DEV 部署失败" -ForegroundColor Red
} else {
    Write-Host "  ✓ DEV 已部署" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 2. STAGING 环境 - 蓝绿发布
# ---------------------------------------------------------------------------
Write-Host "[2/3] 部署 STAGING 环境 (蓝绿)..." -ForegroundColor Yellow
kubectl apply -k "$K8S_DIR\overlays\staging"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ✗ STAGING 部署失败" -ForegroundColor Red
} else {
    Write-Host "  ✓ STAGING 已部署" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 3. PROD 环境 - 蓝绿发布
# ---------------------------------------------------------------------------
Write-Host "[3/3] 部署 PROD 环境 (蓝绿+手动推进)..." -ForegroundColor Yellow
kubectl apply -k "$K8S_DIR\overlays\prod"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ✗ PROD 部署失败" -ForegroundColor Red
} else {
    Write-Host "  ✓ PROD 已部署" -ForegroundColor Green
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " 部署完成 - 验证" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "查看 Pod 状态:"
Write-Host "  kubectl get pods -n tomcat-dev,tomcat-staging,tomcat-prod"
Write-Host ""
Write-Host "查看 Rollout 状态:"
Write-Host "  kubectl get rollout -A"
Write-Host ""
Write-Host "手动推进 STAGING 蓝绿:"
Write-Host "  kubectl argo rollouts promote tomcat-app -n tomcat-staging"
Write-Host ""
Write-Host "手动推进 PROD 蓝绿:"
Write-Host "  kubectl argo rollouts promote tomcat-app -n tomcat-prod"
