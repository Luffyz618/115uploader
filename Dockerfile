# ========= 1) 构建阶段 =========
FROM golang:1.23-alpine AS builder

RUN apk add --no-cache git ca-certificates && update-ca-certificates

WORKDIR /src
COPY fake115uploader ./

# 下载依赖
RUN go mod tidy

# 编译为静态二进制 (编译整个目录，而不是单个 main.go)
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/fake115uploader .

# ========= 2) 运行阶段 =========
FROM docker.m.daocloud.io/library/alpine:3.19

# 关键：加 util-linux（提供 script）；coreutils（提供 stdbuf）作为兜底
RUN apk add --no-cache ca-certificates tzdata bash inotify-tools util-linux coreutils && update-ca-certificates

WORKDIR /config

# 复制编译好的程序
COPY --from=builder /out/fake115uploader /usr/local/bin/fake115uploader

# 复制监控脚本
COPY watcher.sh /watcher.sh
RUN chmod +x /watcher.sh

# 默认执行监控脚本
CMD ["/watcher.sh"]
