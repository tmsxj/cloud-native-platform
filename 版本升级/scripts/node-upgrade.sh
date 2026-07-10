#!/bin/bash
# 通用节点升级脚本（kubeadm v1.29 离线升级用）
# 在目标节点以 root(sudo) 执行；二进制须已 scp 到本机 /tmp（kubeadm/kubelet/kubectl）
# 关键：cp 之后必须 chmod 755，否则 /usr/bin/kubelet 丢执行位 → systemd 无法启动 kubelet → etcd 阶段超时回滚
set -u
echo "=== [1] copy binaries + chmod 755 (CRITICAL: keep exec bit) ==="
cp -f /tmp/kubeadm /usr/bin/kubeadm
cp -f /tmp/kubectl /usr/bin/kubectl
cp -f /tmp/kubelet /usr/bin/kubelet
chmod 755 /usr/bin/kubelet /usr/bin/kubeadm /usr/bin/kubectl
ls -l /usr/bin/kubelet /usr/bin/kubeadm /usr/bin/kubectl
echo "=== [2] restart kubelet with new binary ==="
systemctl restart kubelet
sleep 8
echo "kubelet active: $(systemctl is-active kubelet)"
/usr/bin/kubelet --version
echo "=== [3] kubeadm upgrade node (NO --control-plane flag in 1.29) ==="
kubeadm upgrade node
echo "UPG_RC=$?"
echo "=== [4] final kubelet status ==="
systemctl is-active kubelet
