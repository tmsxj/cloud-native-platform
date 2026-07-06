#!/bin/bash
# 检查 managed Prometheus targets
echo 123 | sudo -S kubectl exec -n monitoring prometheus-managed-0 -c prometheus -- wget -qO- http://localhost:9090/api/v1/targets 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)['data']
active = data['activeTargets']
dropped = data['droppedTargets']
print(f'=== Active Targets: {len(active)} ===')
for t in active:
    labels = t.get('labels', {})
    job = labels.get('job', '?')
    instance = labels.get('instance', '?')
    health = t.get('health', '?')
    icon = 'UP' if health == 'up' else 'DOWN'
    print(f'  [{icon}] {job:35s} {instance}')
if dropped:
    print(f'=== Dropped Targets: {len(dropped)} ===')
    for t in dropped[:5]:
        discovered = t.get('discoveredLabels', {})
        addr = discovered.get('__address__', '?')
        print(f'  DROPPED: {addr}')
"
