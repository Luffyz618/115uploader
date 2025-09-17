# 📦 115uploader

[![Docker Hub](https://img.shields.io/docker/pulls/luffy168/115uploader.svg)](https://hub.docker.com/r/luffy168/115uploader)

基于 Docker 的 **115 网盘自动上传工具**。  
目录监控，自动上传至115网盘，支持秒传和普通上传，递归上传文件 / 文件夹，上传完成后可选删除本地文件，并生成上传日志。  

> ⚠️ 本项目基于 [fake115uploader](https://github.com/orzogc/fake115uploader) 二次开发，感谢原作者的贡献 🙏

---

## ✨ 功能特性
- 📂 **自动监控**：监听指定目录，有新文件/文件夹自动上传到 115  
- 🔄 **递归上传**：支持整目录递归上传  
- 🗑 **上传完成后可选删除**（测试功能，谨慎开启，默认不删除）  
- 🐳 **Docker 一键运行**：开箱即用，配置简单  

---

## 🚀 快速开始

### 1. 拉取镜像
```bash
docker pull luffy168/115uploader:latest
```

### 2. 使用 docker-compose 部署
创建 `docker-compose.yml`：

```yaml
services:
  115uploader:
    image: luffy168/115uploader:latest
    container_name: 115uploader
    environment:
      - COOKIE_115=你的115cookie   # ⚠️ 必填：115 登录 Cookie
      - CID=你的CID                # ⚠️ 必填：网盘目标文件夹 ID（上传到哪个目录）
      - AUTO_DELETE=false          # 可选：是否上传完成后删除本地文件（默认 false）
    volumes:
      - ./config:/config           # 存放配置和日志
      - ./upload:/data             # 存放待上传文件
    restart: unless-stopped
```

然后运行：

```bash
docker compose up -d
```

---

## ⚙️ 环境变量说明

| 变量名        | 必填 | 默认值 | 说明                                   |
|---------------|------|--------|----------------------------------------|
| `COOKIE_115`  | ✅   | 无     | 115 登录 Cookie                        |
| `CID`         | ✅   | 0      | 上传目标目录 ID                        |
| `AUTO_DELETE` | ❌   | false  | 上传成功后是否删除本地文件（true/false） |

---

## 📂 挂载目录说明

| 本地目录   | 容器目录  | 用途                                     |
|------------|-----------|------------------------------------------|
| `./config` | `/config` | 存放配置和日志（`upload.log`、cookie 配置等） |
| `./upload` | `/data`   | 待上传文件/文件夹放这里                  |

---

## 📖 使用方法
1. 将要上传的文件放到 `upload/` 目录  
2. 容器会自动检测并上传到 115  
3. 上传成功后：  
   - `AUTO_DELETE=true` → 本地文件会被删除  
   - `AUTO_DELETE=false` → 本地文件保留  
4. 上传记录可在 `config/upload.log` 查看  
  
---

## 🤝 致谢
- [orzogc/fake115uploader](https://github.com/orzogc/fake115uploader) 提供了基础实现  
- 本项目在其基础上增加了 Docker 化封装、自动监控上传、日志清理等功能  

---

## 📄 开源协议
本项目使用 **GNU General Public License v3.0 (GPL-3.0)** 协议开源。  
