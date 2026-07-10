#!/bin/bash
# 重建升级前被删除的双网格注入 webhook
# 坑: istiod / linkerd-proxy-injector 不会自动重建已删除的 webhook 配置（只 patch 已存在的）。
# 解决: 用原安装清单重放 —— Istio 用当时生成的 istio-final.yaml，Linkerd 从 control-plane.yaml 抽取 webhook 段。
# 在 m1 上以 sudo 执行；KUBECONFIG 已 export。
export KUBECONFIG=/etc/kubernetes/admin.conf
cd /tmp

echo "=== rebuild Linkerd injector webhook (extract MutatingWebhookConfiguration doc) ==="
if [ -f linkerd-control-plane.yaml ]; then
  rm -f lwh*.yaml
  csplit -z -f lwh -b '%02d.yaml' linkerd-control-plane.yaml '/^---$/' '{*}' 2>/dev/null
  for f in lwh*.yaml; do
    if grep -q "kind: MutatingWebhookConfiguration" "$f"; then
      echo "-- apply $f --"
      kubectl apply -f "$f"
    fi
  done
else
  echo "WARN: linkerd-control-plane.yaml not found in /tmp, skip Linkerd webhook"
fi

echo "=== rebuild Istio webhooks (re-apply istio-final.yaml, idempotent) ==="
if [ -f /tmp/istio-final.yaml ]; then
  kubectl apply -f /tmp/istio-final.yaml 2>&1 | grep -iE "webhook|configured|unchanged|created" | head
else
  echo "WARN: istio-final.yaml not found in /tmp, skip Istio webhook"
fi

echo "=== webhooks now ==="
kubectl get mutatingwebhookconfigurations,validatingwebhookconfigurations -o name
