#!/bin/bash
# 在 m1（控制面）以 root 执行：把本地仓库自签 CA 注入 Kyverno 准入控制器信任库。
# 背景：本版本 Kyverno 的 registry 配置中 `ca` 字段不会注入到 cosign 验签拉取的 TLS 信任池，
#      导致对本仓库 HTTPS 拉取签名时始终报 "x509: certificate signed by unknown authority"。
#      通过 initContainer 把 CA 追加进 /etc/ssl/certs/ca-certificates.crt 解决。
set -e
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "== 1) 创建 CA ConfigMap =="
kubectl -n kyverno apply -f kyverno-localreg-ca.yaml

echo "== 2) patch 准入控制器：注入 CA 到系统信任库 =="
kubectl -n kyverno patch deploy kyverno-admission-controller --type=json -p='[
  {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"localreg-ca","configMap":{"name":"kyverno-localreg-ca"}}},
  {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"ca-trust","emptyDir":{}}},
  {"op":"add","path":"/spec/template/spec/initContainers/-","value":{"name":"trust-localreg","image":"192.168.1.61:5000/unsigned/busybox:1.36","command":["/bin/sh","-c"],"args":["cp -r /etc/ssl/certs/. /ca-trust/ 2>/dev/null; cat /localreg-ca/localreg.crt >> /ca-trust/ca-certificates.crt"],"volumeMounts":[{"name":"localreg-ca","mountPath":"/localreg-ca"},{"name":"ca-trust","mountPath":"/ca-trust"}]}},
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"ca-trust","mountPath":"/etc/ssl/certs"}},
  {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"COSIGN_EXPERIMENTAL","value":"0"}}
]'

echo "== 3) 重启准入控制器生效 =="
kubectl -n kyverno rollout restart deploy kyverno-admission-controller
kubectl -n kyverno rollout status deploy kyverno-admission-controller --timeout=120s
echo "DONE"
