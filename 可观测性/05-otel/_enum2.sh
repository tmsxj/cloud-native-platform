#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
OUT=/tmp/lgtm_out.txt
: > $OUT
echo "=== Loki storage backend ===" >> $OUT
kubectl -n monitoring get cm loki-config -o yaml 2>/dev/null | grep -iE "backend|s3|bucket|endpoint|minio|filesystem|boltdb" >> $OUT || echo "no loki-config" >> $OUT
echo "" >> $OUT
echo "=== PVC (monitoring) ===" >> $OUT
kubectl -n monitoring get pvc 2>/dev/null >> $OUT || echo "no pvc" >> $OUT
echo "" >> $OUT
echo "=== StorageClass ===" >> $OUT
kubectl get sc 2>/dev/null >> $OUT
echo "" >> $OUT
echo "=== otel-collector exporters/service ===" >> $OUT
kubectl -n monitoring get cm otel-collector -o yaml 2>/dev/null | sed -n '/exporters/,/service:/p' >> $OUT
echo "" >> $OUT
echo "=== grafana datasource types/urls ===" >> $OUT
kubectl -n monitoring get cm grafana-datasources -o yaml 2>/dev/null | grep -iE "type:|url:|name:" >> $OUT
echo "" >> $OUT
echo "=== tempo/minio exist? ===" >> $OUT
kubectl -n monitoring get deploy,sts,svc 2>/dev/null | grep -iE "tempo|minio" >> $OUT || echo "NONE" >> $OUT
echo "=== DONE ===" >> $OUT
