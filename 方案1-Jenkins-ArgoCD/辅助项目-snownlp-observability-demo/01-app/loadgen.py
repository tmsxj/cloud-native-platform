"""
snownlp-loadgen: 持续压测脚本
=============================
每 1-5 秒随机发送一条情感分析请求到 snownlp-demo，
产生持续的可观测数据（trace + 日志 + 指标）。

作用: 演示环境需要持续流量来展示调用链，没有真实用户时用它模拟。
"""

import time
import random
import json
import urllib.request

# 正面情感测试语料
POSITIVE = [
    "今天天气真好，心情很愉快",
    "这个产品非常好用，强烈推荐",
    "服务态度特别好，下次还会来",
    "物流很快，商品质量也很棒",
    "性价比很高，值得购买",
    "功能很强大，界面也很美观",
    "客服很耐心，问题解决得很及时",
    "包装很精美，送礼很合适",
]

# 负面情感测试语料
NEGATIVE = [
    "产品质量太差了，用了两天就坏了",
    "物流太慢，等了一个星期才到",
    "客服态度恶劣，投诉也没人管",
    "价格太贵了，完全不值这个价",
    "界面太难用了，找了半天找不到功能",
    "包装破损严重，里面的东西都变形了",
    "功能缺失，和描述不符",
    "售后服务太差，维修要等很久",
]

print("=== Load Generator Started ===")
while True:
    # 每次随机选正面或负面语料库中的一条
    sentences = random.choice([POSITIVE, NEGATIVE])
    text = random.choice(sentences)

    # 构造 JSON 请求体
    data = json.dumps({"text": text}).encode()

    try:
        # 通过 K8s Service DNS 名称访问（集群内通信）
        req = urllib.request.Request(
            "http://snownlp-demo/predict",
            data=data,
            headers={"Content-Type": "application/json"},
        )
        resp = urllib.request.urlopen(req, timeout=5)
        result = resp.read().decode()
        print(
            f"[{time.strftime('%H:%M:%S')}] "
            f"POST /predict text={text[:20]}... → {result}"
        )
    except Exception as e:
        print(f"[{time.strftime('%H:%M:%S')}] ERROR: {e}")

    # 随机间隔 1-5 秒，模拟真实用户行为
    time.sleep(random.randint(1, 5))
