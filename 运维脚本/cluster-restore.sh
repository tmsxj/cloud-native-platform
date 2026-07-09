#!/usr/bin/env bash
# 聚焦模式：恢复集群 —— 依据 cluster-focus.sh 生成的快照，把每个工作负载恢复回原始副本数。
# 用法: bash cluster-restore.sh
set -u
export KUBECONFIG=/etc/kubernetes/admin.conf
SNAP="/root/cluster-replica-snapshot.tsv"
if [ ! -f "$SNAP" ]; then
  echo "[restore] 找不到快照 $SNAP，无法恢复（请确认曾执行过 cluster-focus.sh）"
  exit 1
fi
echo "[restore] 按快照恢复副本数 ..."
while IFS=$'\t' read -r KIND NS NAME REP; do
  [ -z "$NS" ] && continue
  if kubectl scale "$KIND" --replicas="$REP" -n "$NS" >/dev/null 2>&1; then
    echo "  restored $NS/$NAME -> $REP"
  else
    echo "  WARN failed $NS/$NAME (可能已被删除，需重新 apply/helm install)"
  fi
done < "$SNAP"
echo "[restore] 完成。可执行 kubectl top nodes 核对资源回升。"
