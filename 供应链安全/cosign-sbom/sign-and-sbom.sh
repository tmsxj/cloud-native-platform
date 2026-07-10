#!/bin/bash
# 在 h1（192.168.1.61，本地仓库宿主机）以 root 执行。
# 演示：生成 cosign 密钥对 -> 对镜像签名 -> 校验 -> 生成 SBOM。
# 注意：本脚本会重新生成密钥；若用于已有集群，需同步更新
#       require-signed-images 策略里的 publicKeys（见 ../kyverno-verify 或
#       策略即代码-Kyverno/policies/require-signed-images.yaml）。
set -e
export COSIGN_PASSWORD=cosign          # 非交互生成密钥用的口令
REG=192.168.1.61:5000
COSIGN=/usr/local/bin/cosign
SYFT=/usr/local/bin/syft

cd /root

# 1) 生成密钥对（必须用 cosign 原生 generate-key-pair；
#    本环境 cosign v2.2.3 拒绝 openssl 生成的任何 PEM 格式，只认自己的 SIGSTORE PRIVATE KEY）。
echo "== 生成 cosign 密钥对 =="
$COSIGN generate-key-pair

# 2) 对镜像签名（--key 用私钥；identity 自动记为 $REG/signed/nginx）
echo "== 对 signed/nginx:1.25 签名 =="
echo y | $COSIGN sign --key cosign.key $REG/signed/nginx:1.25

# 3) 用公钥校验（确认 identity 为 $REG/signed/nginx）
echo "== 校验签名 =="
$COSIGN verify --key cosign.pub $REG/signed/nginx:1.25 | grep -o '"docker-reference":"[^"]*"'

# 4) 生成 SBOM（syft -> SPDX json）
echo "== 生成 SBOM =="
$SYFT $REG/signed/nginx:1.25 -o spdx-json > /root/sbom-nginx.spdx.json
echo "SBOM 已生成：/root/sbom-nginx.spdx.json"
