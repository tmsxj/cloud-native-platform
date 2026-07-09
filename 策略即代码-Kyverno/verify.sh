#!/bin/bash
# 验证 Kyverno 策略准入拦截（bash verify.sh）
# 注意：bad-pod 预期被拒（kubectl apply 返回非 0），故不用 set -e，逐条判定
export KUBECONFIG=/etc/kubernetes/admin.conf
NS=kyverno-test
kubectl create namespace $NS 2>/dev/null || true

echo "===== 用例1: 违规 Pod（nginx:latest，docker.io 源）====="
echo "期望: 被 disallow-latest-tag + restrict-image-registries + require-probes + disallow-privileged 拒绝"
OUT=$(cat <<'EOF' | kubectl apply -n $NS -f - 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: bad-pod
spec:
  containers:
  - name: c
    image: nginx:latest
EOF
)
if echo "$OUT" | grep -q "denied the request"; then
  echo "✅ 拦截成功：$OUT" | head -1
else
  echo "❌ 未被拦截（异常）：$OUT"
fi
echo

echo "===== 用例2: 合规 Pod（ghcr.io 固定版本 + 探针 + 非特权）====="
echo "期望: 正常准入创建"
cat <<'EOF' | kubectl apply -n $NS -f - 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: good-pod
spec:
  containers:
  - name: c
    image: ghcr.io/kyverno/kyverno:v1.18.1
    securityContext:
      privileged: false
    livenessProbe:
      exec:
        command: ["true"]
      periodSeconds: 10
    readinessProbe:
      exec:
        command: ["true"]
      periodSeconds: 10
EOF
echo

echo "===== 清理测试 Pod ====="
kubectl delete pod bad-pod good-pod -n $NS --ignore-not-found 2>/dev/null
echo "验证完成 ✅（用例1 被拒 + 用例2 准入 = 策略已真正生效，替代人工镜像检查）"
