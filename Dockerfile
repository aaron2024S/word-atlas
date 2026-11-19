# syntax=docker/dockerfile:1

# ---- 构建阶段 ------------------------------------------------------------
# 产物是纯静态文件（HTML/JS/CSS + 插画 + 音频），与 CPU 架构无关，
# 所以固定在构建机架构上跑 npm ci / vite build，arm64 镜像不需要 QEMU 模拟。
FROM --platform=$BUILDPLATFORM node:22-alpine AS build

WORKDIR /app

# playwright 只是本地出图脚本用的开发依赖，跳过浏览器下载，省几百 MB 和几分钟
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_SKIP_BROWSER_GC=1 \
    npm_config_update_notifier=false \
    npm_config_fund=false

# 先只拷依赖清单，命中层缓存：源码改动时不必重装 node_modules
COPY package.json package-lock.json ./
RUN npm ci --no-audit

# 再拷源码与素材，执行 tsc -b && vite build，产物在 /app/dist
COPY . .
RUN npm run build

# ---- 运行阶段 ------------------------------------------------------------
FROM nginx:stable-alpine AS runtime

COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -q --spider http://127.0.0.1/ || exit 1

# nginx 官方镜像自带 CMD，无需覆盖
