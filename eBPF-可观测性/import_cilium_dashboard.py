import json, urllib.request, base64

GRAFANA = "http://10.104.87.170"
import os
with open(os.path.expanduser('~/cilium-dashboard.json'), encoding='utf-8-sig') as f:
    dash = json.load(f)

payload = {"dashboard": dash, "overwrite": True}
auth = base64.b64encode(b"admin:admin").decode()
req = urllib.request.Request(
    GRAFANA + "/api/dashboards/db",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json", "Authorization": "Basic " + auth},
    method="POST",
)
try:
    resp = urllib.request.urlopen(req)
    print("HTTP", resp.status)
    print(resp.read().decode())
except urllib.error.HTTPError as e:
    print("HTTP", e.code)
    print(e.read().decode())
