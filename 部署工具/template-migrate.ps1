#!/usr/bin/env pwsh
# ============================================================================
# YAML 模板迁移脚本 — 将硬编码值替换为 ${VAR} 占位符
# ============================================================================
# 运行后将兼容 envsubst 预处理，换集群只需改 env.sh
# 用法: pwsh template-migrate.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " YAML 模板迁移: 硬编码 → `#{VAR} 占位符" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$files = @()

# ---- 搜索所有包含 192.168.1.61 的 YAML/YML 文件 ----
Write-Host "[1/5] 查找包含 Harbor IP 的 YAML 文件..." -ForegroundColor Yellow
$harborFiles = Get-ChildItem -Path $Root -Recurse -Include "*.yaml","*.yml","*.gitlab-ci.yml" `
    | Where-Object { 
        $_.DirectoryName -notmatch "backup-" -and 
        $_.DirectoryName -notmatch "HiAgent" 
    } `
    | Select-String -Pattern "192\.168\.1\.61" -List `
    | Select-Object -ExpandProperty Path

Write-Host "  找到 $($harborFiles.Count) 个涉及 Harbor IP 的文件"

foreach ($file in $harborFiles) {
    $content = Get-Content -Path $file -Raw -Encoding UTF8
    $original = $content
    
    # 替换镜像地址中的 IP (保留 library/ monitoring/ demo/ tomcat-demo/ 等路径)
    # 不要替换 sealed-secrets/example-secret.yaml 中的 JSON key (line 20)
    if ($file -match "example-secret") {
        # 只为 example-secret 处理 --docker-server 等引用，不处理 JSON key
        $content = $content -replace "(?<!`")(?<! )192\.168\.1\.61(?!/library|/monitoring|/tomcat|/demo)", '${HARBOR_IP}'
    }
    $content = $content -replace "192\.168\.1\.61/library/", '${HARBOR_IP}/library/'
    $content = $content -replace "192\.168\.1\.61/monitoring/", '${HARBOR_IP}/monitoring/'
    $content = $content -replace "192\.168\.1\.61/tomcat-demo/", '${HARBOR_IP}/tomcat-demo/'
    $content = $content -replace "192\.168\.1\.61/demo/", '${HARBOR_IP}/demo/'
    # REGISTRY: 192.168.1.61 (.gitlab-ci.yml)
    $content = $content -replace '(?<=REGISTRY:\s)192\.168\.1\.61$', '${HARBOR_IP}'
    $content = $content -replace '(?<=REGISTRY:\s)"192\.168\.1\.61"', '"${HARBOR_IP}"'
    # --insecure-registry flag
    $content = $content -replace '(?<=--insecure-registry=)192\.168\.1\.61(?=")', '${HARBOR_IP}'
    # Prometheus scrape target
    $content = $content -replace '- 192\.168\.1\.61:9090', '- ${HARBOR_IP}:9090'
    # docker login / docker-server in comments
    $content = $content -replace 'docker-server=192\.168\.1\.61', 'docker-server=${HARBOR_IP}'
    
    if ($content -ne $original) {
        Set-Content -Path $file -Value $content -Encoding UTF8 -NoNewline
        $relPath = $file.Replace($Root + "\", "")
        Write-Host "  ✓ $relPath" -ForegroundColor Green
    }
}

# ---- 替换 storageClassName: local-path ----
Write-Host ""
Write-Host "[2/5] 替换 StorageClass 硬编码..." -ForegroundColor Yellow
$scFiles = Get-ChildItem -Path $Root -Recurse -Include "*.yaml","*.yml" `
    | Where-Object { $_.DirectoryName -notmatch "backup-" -and $_.DirectoryName -notmatch "HiAgent" } `
    | Select-String -Pattern "storageClassName:\s+local-path" -List `
    | Select-Object -ExpandProperty Path

foreach ($file in $scFiles) {
    $content = Get-Content -Path $file -Raw -Encoding UTF8
    $original = $content
    $content = $content -replace 'storageClassName:\s+local-path(\s+#.*)?', 'storageClassName: ${STORAGE_CLASS}$1'
    
    if ($content -ne $original) {
        Set-Content -Path $file -Value $content -Encoding UTF8 -NoNewline
        $relPath = $file.Replace($Root + "\", "")
        Write-Host "  ✓ $relPath" -ForegroundColor Green
    }
}

# ---- 替换 ingressClassName: nginx ----
Write-Host ""
Write-Host "[3/5] 替换 IngressClass 硬编码..." -ForegroundColor Yellow
$ingFiles = Get-ChildItem -Path $Root -Recurse -Include "*.yaml","*.yml" `
    | Where-Object { $_.DirectoryName -notmatch "backup-" -and $_.DirectoryName -notmatch "HiAgent" } `
    | Select-String -Pattern "ingressClassName:\s+nginx" -List `
    | Select-Object -ExpandProperty Path

foreach ($file in $ingFiles) {
    $content = Get-Content -Path $file -Raw -Encoding UTF8
    $original = $content
    $content = $content -replace 'ingressClassName:\s+nginx(\s+#.*)?', 'ingressClassName: ${INGRESS_CLASS}$1'
    
    if ($content -ne $original) {
        Set-Content -Path $file -Value $content -Encoding UTF8 -NoNewline
        $relPath = $file.Replace($Root + "\", "")
        Write-Host "  ✓ $relPath" -ForegroundColor Green
    }
}

# ---- 替换域名硬编码 (gitlab.test / jenkins.test) ----
Write-Host ""
Write-Host "[4/5] 替换域名硬编码..." -ForegroundColor Yellow

# 替换 external_url 和健康检查中的 gitlab.test
$domainFiles = @("配置文件\gitlab\gitlab-deploy.yaml", "配置文件\gitlab\gitlab-runner-deploy.yaml")
foreach ($pattern in $domainFiles) {
    $files = Get-ChildItem -Path $Root -Recurse -Include "*.yaml","*.yml" `
        | Where-Object { $_.FullName -match [regex]::Escape($pattern) }
    foreach ($file in $files) {
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        $original = $content
        $content = $content -replace "gitlab\.test", '${GITLAB_DOMAIN}'
        $content = $content -replace "jenkins\.test", '${JENKINS_DOMAIN}'
        
        if ($content -ne $original) {
            Set-Content -Path $file.FullName -Value $content -Encoding UTF8 -NoNewline
            Write-Host "  ✓ $($file.Name)" -ForegroundColor Green
        }
    }
}

# 替换 jenkins-deploy.yaml 中的域名
$jenkinsFile = Get-ChildItem -Path $Root -Recurse -Include "jenkins-deploy.yaml" | Where-Object { $_.DirectoryName -notmatch "backup-" }
foreach ($file in $jenkinsFile) {
    $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    $original = $content
    $content = $content -replace "(?<=host:\s)jenkins\.test", '${JENKINS_DOMAIN}'
    $content = $content -replace "http://jenkins\.test:31716", 'http://${JENKINS_DOMAIN}:${NODE_PORT}'
    
    if ($content -ne $original) {
        Set-Content -Path $file.FullName -Value $content -Encoding UTF8 -NoNewline
        Write-Host "  ✓ $($file.Name)" -ForegroundColor Green
    }
}

# ---- 替换 NodePort (在 YAML 注释中) ----
Write-Host ""
Write-Host "[5/5] 替换 NodePort 硬编码..." -ForegroundColor Yellow
$portFiles = Get-ChildItem -Path $Root -Recurse -Include "*.yaml","*.yml" `
    | Where-Object { $_.DirectoryName -notmatch "backup-" -and $_.DirectoryName -notmatch "HiAgent" } `
    | Select-String -Pattern ":31716" -List `
    | Select-Object -ExpandProperty Path

foreach ($file in $portFiles) {
    $content = Get-Content -Path $file -Raw -Encoding UTF8
    $original = $content
    # 只替换注释中和 URL 中的 31716
    $content = $content -replace ':31716', ':${NODE_PORT}'
    
    if ($content -ne $original) {
        Set-Content -Path $file -Value $content -Encoding UTF8 -NoNewline
        $relPath = $file.Replace($Root + "\", "")
        Write-Host "  ✓ $relPath" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " ✅ 迁移完成！所有 YAML 已变量化" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "下一步: 修改 env.sh 填入实际值，然后执行:" -ForegroundColor White
Write-Host "  source ./env.sh" -ForegroundColor Yellow
Write-Host "  source ./deploy-helper.sh" -ForegroundColor Yellow
Write-Host "  kubectl_apply_template <你的yaml文件>" -ForegroundColor Yellow
Write-Host ""
Write-Host "或直接使用一键部署脚本:" -ForegroundColor White
Write-Host "  方案1/配置文件/scripts/one-click-init.sh" -ForegroundColor Yellow
Write-Host "  方案2/配置文件/scripts/one-click-init.sh" -ForegroundColor Yellow
