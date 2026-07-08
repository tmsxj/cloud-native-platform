import json, urllib.request, urllib.error, base64, os

GRAFANA = "http://10.104.87.170"
with open(os.path.expanduser('~/ds_cilium.json'), encoding='utf-8-sig') as f:
    ds = json.load(f)

auth = base64.b64encode(b"admin:admin").decode()
req = urllib.request.Request(
    GRAFANA + "/api/datasources",
    data=json.dumps(ds).encode(),
    headers={"Content-Type": "application/json", "Authorization": "Basic " + auth},
    method="POST",
)
try:
    r = urllib.request.urlopen(req)
    print("HTTP", r.status)
    print(r.read().decode())
except urllib.error.HTTPError as e:
    print("HTTP", e.code)
    print(e.read().decode())
