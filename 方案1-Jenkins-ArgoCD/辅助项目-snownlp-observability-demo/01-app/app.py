"""
snownlp-demo: 情感分析微服务
=============================
集成 SkyWalking Python Agent 实现分布式追踪，
日志自动注入 trace_id，Prometheus 指标暴露。

可观测性特征：
- 每个 HTTP 请求自动创建 SkyWalking Entry Span（Layer=Http）
- 日志每行携带 trace_id，通过 Loki → Grafana → SkyWalking 一键跳转
- /metrics 端点暴露 Prometheus 指标

架构位置: 链路起点 —— 产生 trace 和日志的源头
"""

# ============================================================
# 依赖导入
# ============================================================
from fastapi import FastAPI, Request
from pydantic import BaseModel
from snownlp import SnowNLP                # 中文情感分析引擎
import logging
import time
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from starlette.responses import Response
from skywalking import Layer               # 用于标注 Span 的层级类型
from skywalking.trace.context import get_context  # 获取当前请求的 SW 上下文

# ============================================================
# Prometheus 指标定义
# 通过 /metrics 端点暴露，Prometheus 定期抓取
# ============================================================
REQUEST_COUNT = Counter(
    'http_requests_total',              # 请求计数器（rate 计算 QPS）
    'Total HTTP requests',
    ['method', 'endpoint', 'http_status']
)
REQUEST_LATENCY = Histogram(
    'http_request_duration_seconds',    # 请求延迟直方图（计算 P50/P95/P99）
    'HTTP request latency',
    ['method', 'endpoint']
)

app = FastAPI()


# ============================================================
# 中间件1: SkyWalking 分布式追踪 —— 【核心，面试重点】
# ============================================================
# 为什么需要手动创建 Entry Span？
# FastAPI 的 ASGI 中间件运行在 SkyWalking agent 的自动埋点层之外，
# 如果不手动创建 Entry Span，SkyWalking UI 中看不到这个 HTTP 端点。
#
# 关键点:
#   1. get_context() → 获取 SkyWalking 当前追踪上下文
#   2. new_entry_span() → 创建一个入口 Span（表示这是请求的起点）
#   3. span.layer = Layer.Http → 标注为 HTTP 层，UI 中才会正确展示拓扑图
#   4. op = "POST:/predict" → Span 的操作名，在调用链中一目了然
# ============================================================
@app.middleware("http")
async def sw_trace_middleware(request: Request, call_next):
    # 构造操作名: 如 "POST:/predict"、"GET:/health"
    op = f"{request.method}:{request.url.path}"
    ctx = get_context()
    # 创建入口 Span，span 的生命周期由 with 语句管理
    with ctx.new_entry_span(op=op) as span:
        span.layer = Layer.Http  # 【关键】标注为 HTTP 层，否则 UI 无法识别
        response = await call_next(request)
        return response


# ============================================================
# 中间件2: Prometheus 指标采集
# 记录每个请求的延迟和状态码，供 Prometheus 抓取
# ============================================================
@app.middleware("http")
async def add_metrics(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    duration = time.time() - start
    # 记录延迟（秒）
    REQUEST_LATENCY.labels(
        method=request.method, endpoint=request.url.path
    ).observe(duration)
    # 记录请求计数
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.url.path,
        http_status=response.status_code
    ).inc()
    return response


# ============================================================
# /metrics 端点 —— Prometheus 抓取入口
# Deployment 的 annotations 已配置 prometheus.io/scrape: "true"
# Prometheus 会自动发现并抓取此端点
# ============================================================
@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


# ============================================================
# trace_id 日志注入 —— 【核心，面试重点】
# ============================================================
# 工作原理:
#   1. Python logging 框架支持 Filter 机制
#   2. SafeSWFilter.filter() 在每个日志记录前被调用
#   3. 从 SkyWalking 上下文中提取 related_traces[0] 作为 trace_id
#   4. 注入到 LogRecord 的 trace_id 属性
#   5. 日志格式化字符串 %(trace_id)s 自动替换为实际值
#
# 安全降级: 当 SW 上下文不可用时（如启动阶段），trace_id 输出 "N/A"
# ============================================================
class SafeSWFilter(logging.Filter):
    """从 SkyWalking 上下文提取 trace_id，注入到每条日志中"""
    def filter(self, record):
        try:
            ctx = get_context()
            if ctx and ctx.segment:
                # related_traces[0] 是当前 segment 关联的 trace 列表的第一个
                # 对于 entry span，这就是自己的 traceId
                record.trace_id = str(ctx.segment.related_traces[0])
            else:
                record.trace_id = "N/A"
        except Exception:
            record.trace_id = "N/A"  # 安全降级：任何异常都不影响业务日志输出
        return True


# ============================================================
# 日志系统配置
# ============================================================
# 应用日志 —— 输出到 stdout，被容器运行时捕获写入 /var/log/pods/
# 日志格式中必须包含 trace_id 字段，否则 Promtail 无法提取
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] trace_id=%(trace_id)s %(message)s'
)
logger = logging.getLogger(__name__)
logger.addFilter(SafeSWFilter())

# Uvicorn 访问日志 —— 也注入 trace_id
# 关键: 必须先 handlers.clear() 清除默认 handler，否则会重复输出
# 同时也要 addFilter(SafeSWFilter()) 确保访问日志也有 trace_id
uvicorn_logger = logging.getLogger("uvicorn.access")
handler = logging.StreamHandler()
handler.setFormatter(logging.Formatter(
    '%(asctime)s [%(levelname)s] trace_id=%(trace_id)s %(message)s'
))
uvicorn_logger.handlers.clear()  # 清除 uvicorn 默认的日志格式
uvicorn_logger.addHandler(handler)
uvicorn_logger.addFilter(SafeSWFilter())


# ============================================================
# 业务 API
# ============================================================
class TextInput(BaseModel):
    text: str


@app.post("/predict")
async def predict(input: TextInput):
    """
    情感分析接口 —— 核心业务入口
    链路: loadgen → POST /predict → SnowNLP 分析 → 返回结果
    每调用一次产生: 1 个 SkyWalking trace + 1 条日志 + Prometheus 指标
    """
    start_time = time.time()

    # SnowNLP 情感分析: sentiments 返回 0-1 之间分值
    # >=0.5 正面情绪，<0.5 负面情绪
    s = SnowNLP(input.text)
    sentiment_score = s.sentiments
    sentiment = "POSITIVE" if sentiment_score >= 0.5 else "NEGATIVE"
    # 置信度: 离 0.5 越远越确定
    confidence = round(
        sentiment_score if sentiment == "POSITIVE" else 1 - sentiment_score, 4
    )
    delay = time.time() - start_time

    # 日志自动携带 trace_id（由 SafeSWFilter 注入）
    # 这条日志最终出现在 Grafana Loki 面板中，每行末尾是可点击的 SkyWalking 链接
    logger.info(
        f"Prediction: text='{input.text}', "
        f"sentiment={sentiment}, confidence={confidence}, delay={delay:.3f}s"
    )

    return {"sentiment": sentiment, "confidence": confidence}


@app.get("/health")
async def health():
    """健康检查 —— 被 K8s liveness/readiness probe 调用"""
    return {"status": "ok"}
