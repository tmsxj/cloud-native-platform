#!/bin/bash
# ============================================================================
# 部署辅助函数 — envsubst 预处理 + kubectl apply
# ============================================================================
# 自动将 YAML 模板中的 ${VAR} 替换为环境变量值后再部署
#
# 用法:
#   source ./deploy-helper.sh
#   source ./env.sh
#   kubectl_apply_template <yaml文件路径>
#   kubectl_apply_template_dir <目录>        # 批量处理目录下所有 yaml
# ============================================================================

# 单个文件: envsubst 替换后 apply
kubectl_apply_template() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "  ✗ 文件不存在: $file"
        return 1
    fi
    local basename=$(basename "$file")
    echo "  → 部署: $basename"
    envsubst < "$file" | kubectl apply -f -
    local rc=$?
    if [ $rc -eq 0 ]; then
        echo "  ✓ $basename 部署成功"
    else
        echo "  ✗ $basename 部署失败 (exit=$rc)"
        return $rc
    fi
}

# 批量处理目录下所有 .yaml/.yml 文件
kubectl_apply_template_dir() {
    local dir="$1"
    local count=0
    local failed=0
    echo "批量部署: $dir"
    for f in "$dir"/*.yaml "$dir"/*.yml; do
        [ -f "$f" ] || continue
        kubectl_apply_template "$f"
        [ $? -ne 0 ] && ((failed++))
        ((count++))
    done
    echo "完成: $count 个文件, 失败 $failed"
}

# 直接创建资源（envsubst 后 pipe 到 kubectl create）
kubectl_create_template() {
    local yaml_str="$1"
    local desc="$2"
    echo "  → 创建: $desc"
    echo "$yaml_str" | envsubst | kubectl create -f -
}
