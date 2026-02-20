# 多阶段构建 Dockerfile for Huobao Drama

# ==================== 阶段1: 构建前端 ====================
FROM node:lts-alpine3.22 AS frontend-builder

WORKDIR /app/web

COPY web/package*.json ./
RUN npm install

COPY web/ ./
RUN npm run build

# ==================== 阶段2: 构建后端 ====================
FROM golang:tip-alpine3.22 AS backend-builder

ENV GOPROXY=direct
ENV GO111MODULE=on
RUN apk add --no-cache git ca-certificates tzdata openssh-client

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download -x

COPY . .
COPY --from=frontend-builder /app/web/dist ./web/dist

RUN CGO_ENABLED=0 go build -ldflags="-w -s" -o huobao-drama .
RUN CGO_ENABLED=0 go build -ldflags="-w -s" -o migrate cmd/migrate/main.go

# ==================== 阶段3: 运行时镜像 ====================
FROM alpine:3.23.3

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
EXPOSE 5680

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:5680/health || exit 1

CMD ["./huobao-drama"]
