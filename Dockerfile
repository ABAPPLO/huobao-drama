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
# 完全不修改任何系统文件，直接指定源执行apk命令
RUN set -eux; \
    # 直接通过--repository参数指定海外源，无需修改文件
    apk update --no-cache \
      --repository https://nl.alpinelinux.org/alpine/v3.22/main/ \
      --repository https://nl.alpinelinux.org/alpine/v3.22/community/; \
    # 安装工具时同样指定源
    apk add --no-cache \
      --repository https://nl.alpinelinux.org/alpine/v3.22/main/ \
      --repository https://nl.alpinelinux.org/alpine/v3.22/community/ \
      curl wget bash;
      
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
# 完全不修改任何系统文件，直接指定源执行apk命令
RUN set -eux; \
    # 直接通过--repository参数指定海外源，无需修改文件
    apk update --no-cache  \
      --repository https://nl.alpinelinux.org/alpine/v3.22/main/ \
      --repository https://nl.alpinelinux.org/alpine/v3.22/community/; \
    # 安装工具时同样指定源
    apk add --no-cache \
      --repository https://nl.alpinelinux.org/alpine/v3.22/main/ \
      --repository https://nl.alpinelinux.org/alpine/v3.22/community/ \
      curl wget bash;
    
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
