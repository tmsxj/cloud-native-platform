# ============================================================
# Nginx GitOps Demo - Docker 镜像
# ============================================================
# Jenkins 会在构建时注入以下 ARG:
#   BUILD_NUMBER  - Jenkins 构建号
#   BUILD_COMMIT  - Git commit hash (短)
#   BUILD_TIME    - 构建时间
# ============================================================
FROM nginx:alpine

ARG BUILD_NUMBER=local
ARG BUILD_COMMIT=unknown
ARG BUILD_TIME=unknown

# 把构建信息写入页面
RUN echo "<!DOCTYPE html>" > /usr/share/nginx/html/index.html && \
    echo "<html><head><meta charset='utf-8'><title>Nginx GitOps Demo</title>" >> /usr/share/nginx/html/index.html && \
    echo "<style>" >> /usr/share/nginx/html/index.html && \
    echo "  body { font-family: 'Segoe UI', sans-serif; background: #0f172a; color: #e2e8f0; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; }" >> /usr/share/nginx/html/index.html && \
    echo "  .card { background: #1e293b; border-radius: 16px; padding: 48px; box-shadow: 0 25px 50px rgba(0,0,0,0.4); text-align: center; max-width: 600px; }" >> /usr/share/nginx/html/index.html && \
    echo "  h1 { color: #38bdf8; margin: 0 0 8px 0; font-size: 28px; }" >> /usr/share/nginx/html/index.html && \
    echo "  .badge { display: inline-block; background: #334155; color: #94a3b8; padding: 4px 12px; border-radius: 20px; font-size: 13px; margin: 4px; }" >> /usr/share/nginx/html/index.html && \
    echo "  .pipeline { margin-top: 32px; display: flex; gap: 12px; justify-content: center; flex-wrap: wrap; }" >> /usr/share/nginx/html/index.html && \
    echo "  .stage { background: #0f172a; padding: 12px 20px; border-radius: 8px; font-size: 14px; }" >> /usr/share/nginx/html/index.html && \
    echo "  .stage.done { border-left: 3px solid #22c55e; }" >> /usr/share/nginx/html/index.html && \
    echo "  .arrow { color: #38bdf8; font-weight: bold; align-self: center; }" >> /usr/share/nginx/html/index.html && \
    echo "</style></head><body>" >> /usr/share/nginx/html/index.html && \
    echo "<div class='card'>" >> /usr/share/nginx/html/index.html && \
    echo "  <h1>🚀 Nginx GitOps Demo</h1>" >> /usr/share/nginx/html/index.html && \
    echo "  <p style='color:#64748b;font-size:14px'>Jenkins CI → Harbor → Git Push → ArgoCD → K8s</p>" >> /usr/share/nginx/html/index.html && \
    echo "  <div style='margin-top:24px'>" >> /usr/share/nginx/html/index.html && \
    echo "    <span class='badge'>Build #${BUILD_NUMBER}</span>" >> /usr/share/nginx/html/index.html && \
    echo "    <span class='badge'>Commit ${BUILD_COMMIT}</span>" >> /usr/share/nginx/html/index.html && \
    echo "    <span class='badge'>${BUILD_TIME}</span>" >> /usr/share/nginx/html/index.html && \
    echo "  </div>" >> /usr/share/nginx/html/index.html && \
    echo "  <div class='pipeline'>" >> /usr/share/nginx/html/index.html && \
    echo "    <div class='stage done'>📝 Git Push</div>" >> /usr/share/nginx/html/index.html && \
    echo "    <div class='arrow'>→</div>" >> /usr/share/nginx/html/index.html && \
    echo "    <div class='stage done'>🔨 Jenkins Build</div>" >> /usr/share/nginx/html/index.html && \
    echo "    <div class='arrow'>→</div>" >> /usr/share/nginx/html/index.html && \
    echo "    <div class='stage done'>📦 Harbor Registry</div>" >> /usr/share/nginx/html/index.html && \
    echo "    <div class='arrow'>→</div>" >> /usr/share/nginx/html/index.html && \
    echo "    <div class='stage done'>🔄 ArgoCD Sync</div>" >> /usr/share/nginx/html/index.html && \
    echo "    <div class='arrow'>→</div>" >> /usr/share/nginx/html/index.html && \
    echo "    <div class='stage done'>✅ K8s Deploy</div>" >> /usr/share/nginx/html/index.html && \
    echo "  </div>" >> /usr/share/nginx/html/index.html && \
    echo "  <p style='margin-top:32px;color:#475569;font-size:12px'>Served by Nginx in Kubernetes | Host: <span style='color:#94a3b8' id='hostname'>...</span></p>" >> /usr/share/nginx/html/index.html && \
    echo "</div>" >> /usr/share/nginx/html/index.html && \
    echo "<script>document.getElementById('hostname').textContent=window.location.hostname;</script>" >> /usr/share/nginx/html/index.html && \
    echo "</body></html>" >> /usr/share/nginx/html/index.html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
