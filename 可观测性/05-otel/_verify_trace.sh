#!/bin/bash
export KUBECONFIG=/etc/kubernetes/admin.conf
TID=59581040520ed11ef5940b6b52ccb27f
kubectl -n monitoring run tv --rm -i --restart=Never --image=192.168.1.61/library/alpine:latest --command -- sh -c "apk add -q curl >/dev/null 2>&1; echo '--- trace-by-id ---'; curl -s http://tempo.monitoring:3200/api/traces/$TID; echo" 2>/dev/null
