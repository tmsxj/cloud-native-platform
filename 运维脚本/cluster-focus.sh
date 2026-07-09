#!/usr/bin/env bash
# 聚焦模式：冻结集群 —— 除 kube-system（控制面 + Cilium + CoreDNS + metrics-server）外，
# 其余所有命名空间的 Deployment / StatefulSet 全部缩容到 0，留出一个干净、低占用的环境
# 专心做未完成的增强任务（20~31）。恢复请用同目录 cluster-restore.sh。
# 注意: kubectl scale 不支持 "deploy,sts" 逗号写法，必须分开；且要先停 argocd 以免自修复顶回副本。
set -u
export KUBECONFIG=/etc/kubernetes/admin.conf
KEEP="kube-system"
SNAP="/root/cluster-replica-snapshot.tsv"

echo "[focus] 保存当前副本快照 -> $SNAP"
kubectl get deploy,sts -A \
  -o custom-columns='KIND:.kind,NS:.metadata.namespace,NAME:.metadata.name,REP:.spec.replicas' \
  --no-headers 2>/dev/null \
  | grep -vE "^[A-Za-z-]+\s+${KEEP}\s" \
  > "$SNAP"

echo "[focus] 先将 argocd 缩容到 0（避免其自修复 self-heal 抵消后续缩容）"
kubectl scale deploy --all --replicas=0 -n argocd 2>/dev/null
kubectl scale sts --all --replicas=0 -n argocd 2>/dev/null
sleep 6

echo "[focus] 将其余非 kube-system 命名空间的 deploy/sts 缩容至 0 ..."
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  [ "$ns" = "$KEEP" ] && continue
  [ "$ns" = "argocd" ] && continue
  kubectl scale deploy --all --replicas=0 -n "$ns" 2>/dev/null
  kubectl scale sts --all --replicas=0 -n "$ns" 2>/dev/null
  # 兜底：孤儿 ReplicaSet（Deployment 被删但 RS/Pod 残留）也缩到 0
  kubectl scale rs --all --replicas=0 -n "$ns" 2>/dev/null
done

echo "[focus] 完成。当前仅保留: 控制面 + Cilium + CoreDNS + metrics-server (kube-system)"
echo "[focus] 快照记录的待恢复工作负载行数: $(wc -l < "$SNAP")"
kubectl top nodes 2>/dev/null
