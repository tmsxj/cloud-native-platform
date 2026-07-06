# ============================================================
# snownlp-demo 镜像构建
# ============================================================
# 构建: docker build -t <registry>/snownlp-demo:sw-agent .
# 推送: docker push <registry>/snownlp-demo:sw-agent
# ============================================================

FROM python:3.9-slim

WORKDIR /app

# ---- 安装 Python 依赖 ----
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir apache-skywalking
# apache-skywalking 分两次装是因为它的安装过程依赖已安装的 fastapi/uvicorn

# ---- 复制应用代码 ----
# 实际部署时 app.py 通过 ConfigMap 挂载，方便热更新代码不需重新构建镜像
COPY app.py .

# ============================================================
# 【核心】启动方式: sw-python run
# ============================================================
# sw-python 是 SkyWalking Python Agent 提供的包装器:
#   - 自动注入 skywalking 探针到 Python 进程
#   - 拦截所有 HTTP/数据库/gRPC 调用
#   - 将 trace 数据通过 gRPC 上报到 OAP
#
# 不能用 "python app.py"! 那样 SkyWalking agent 不会加载！
#
# ENTRYPOINT + CMD 设计:
#   ENTRYPOINT ["sw-python", "run"]    ← 固定，由 SW agent 接管进程启动
#   CMD ["uvicorn", "app:app", ...]    ← 可被 docker run / K8s args 覆盖
# ============================================================
ENTRYPOINT ["sw-python", "run"]
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
