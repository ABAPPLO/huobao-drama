# 多阶段构建 Dockerfile for Huobao Drama

# ==================== 阶段1: 构建前端 ====================
FROM node:20-alpine AS frontend-builder

WORKDIR /app/web

COPY web/package*.json ./
RUN npm install

COPY web/ ./
RUN npm run build
USER root
# ==================== 阶段2: 构建后端 ====================
FROM golang:1.23-alpine AS backend-builder

ENV GOPROXY=https://proxy.golang.org,direct
ENV GO111MODULE=on
RUN set -eux; \
    # 改用美国官方源（更稳定）
    printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > /etc/resolv.conf; \
    cp /etc/apk/repositories /etc/apk/repositories.bak; \
    # 替换为美国Nexcess节点（海外访问最稳定的官方源之一）
    echo "https://mirror.us-midwest-1.nexcess.net/alpine/v3.22/main/" > /etc/apk/repositories; \
    echo "https://mirror.us-midwest-1.nexcess.net/alpine/v3.22/community/" >> /etc/apk/repositories; \
    # 调试：打印源文件内容，确认替换成功
    cat /etc/apk/repositories; \
    # 调试：测试源连通性
    curl -v --max-time 20 https://mirror.us-midwest-1.nexcess.net/alpine/v3.22/main/ || echo "源访问失败，跳过测试"; \
    # 清空缓存+更新源（重试10次）
    rm -rf /var/cache/apk/*; \
    apk update --no-cache --retries=10;
RUN apk add --no-cache git ca-certificates tzdata

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
COPY --from=frontend-builder /app/web/dist ./web/dist

RUN CGO_ENABLED=0 go build -ldflags="-w -s" -o huobao-drama .
RUN CGO_ENABLED=0 go build -ldflags="-w -s" -o migrate cmd/migrate/main.go

# ==================== 阶段3: 运行时镜像 ====================
FROM alpine:latest
USER root
RUN set -eux; \
    # 改用美国官方源（更稳定）
    printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > /etc/resolv.conf; \
    cp /etc/apk/repositories /etc/apk/repositories.bak; \
    # 替换为美国Nexcess节点（海外访问最稳定的官方源之一）
    echo "https://mirror.us-midwest-1.nexcess.net/alpine/v3.22/main/" > /etc/apk/repositories; \
    echo "https://mirror.us-midwest-1.nexcess.net/alpine/v3.22/community/" >> /etc/apk/repositories; \
    # 调试：打印源文件内容，确认替换成功
    cat /etc/apk/repositories; \
    # 调试：测试源连通性
    curl -v --max-time 20 https://mirror.us-midwest-1.nexcess.net/alpine/v3.22/main/ || echo "源访问失败，跳过测试"; \
    # 清空缓存+更新源（重试10次）
    rm -rf /var/cache/apk/*; \
    apk update --no-cache --retries=10;
    
RUN apk add --no-cache ca-certificates tzdata ffmpeg wget && rm -rf /var/cache/apk/*

ENV TZ=Asia/Shanghai

WORKDIR /app

COPY --from=backend-builder /app/huobao-drama .
COPY --from=backend-builder /app/migrate .
COPY --from=frontend-builder /app/web/dist ./web/dist
COPY configs/config.example.yaml ./configs/
RUN cp ./configs/config.example.yaml ./configs/config.yaml
COPY migrations ./migrations/
RUN mkdir -p /app/data/storage

EXPOSE 5678

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:5678/health || exit 1

CMD ["./huobao-drama"]
