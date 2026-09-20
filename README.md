# FindMy API

一个轻量的 Apple Find My /「查找」物品服务端 API。

本项目基于 FindMy.py，读取本地 Apple 账号会话与 Find My accessory JSON，在服务器后台定时刷新物品位置，并通过 FastAPI 提供只读 JSON 接口。

> 本项目不是 Apple 官方项目，与 Apple Inc. 无关联。Find My 私有接口可能随时变化。请仅用于你自己拥有或已获授权的 Apple ID 与设备/物品。

## 特性

- FastAPI + Uvicorn
- 后台自动刷新，默认每 5 分钟一次
- API 读取本地 cache.json，访问速度快
- 支持多个 Find My accessory
- 自动跳过非 accessory、无 alignment、alignment 过期的数据
- 支持 Query Token 与 Bearer Token
- 支持 CORS
- ani_libs.bin 不存在时交给 FindMy.py 自动初始化
- 提供 Linux 一键安装脚本
- 适合宝塔 Supervisor + Nginx HTTPS 反向代理

## 工作原理

    Apple Find My Network
            ↓
        FindMy.py
            ↓
    Rolling Keys / 加密位置报告解密
            ↓
        后台定时刷新
            ↓
         cache.json
            ↓
         FastAPI
            ↓
      Nginx / HTTPS
            ↓
      Web / App / Client

本项目不负责导出 Find My accessory 私钥 JSON。你需要提前准备：

    account.json
    devices/*.json

ani_libs.bin 可在首次运行 Local Anisette 时自动生成。

## 安全警告

以下文件高度敏感，绝对不要提交到 GitHub、公开网盘或发送给陌生人：

    account.json
    devices/*.json
    .env
    cache.json

其中 devices/*.json 含 Find My accessory 的密钥材料，account.json 含 Apple 账号认证/会话状态。

仓库已经通过 .gitignore 默认忽略这些文件。

## 环境要求

推荐：

- Linux
- Python 3.12
- x86_64 / amd64
- 可正常访问 Apple 相关网络服务

## 快速部署

### 1. 克隆

    git clone https://github.com/likeyun/findmy-api.git
    cd findmy-api

宝塔常用路径：

    cd /www/wwwroot
    git clone https://github.com/likeyun/findmy-api.git
    cd /www/wwwroot/findmy-api

### 2. 一键安装

    chmod +x install.sh
    ./install.sh

安装脚本会自动：

1. 检查 Python 3.12
2. 没有 Python 3.12 时尝试系统包管理器安装
3. 系统仓库没有时自动下载并源码安装 Python 3.12
4. 创建 venv
5. 安装 pip / FindMy / FastAPI / Uvicorn
6. 创建 devices/、logs/
7. 生成本地 .env 与随机 API Token
8. 检查 app.py
9. 设置敏感文件权限

### 3. 上传运行数据

把自己的文件放到：

    findmy-api/
    ├── account.json
    └── devices/
        ├── item-1.json
        ├── item-2.json
        └── ...

不要把这些文件提交到仓库。

### 4. 配置

首次运行 install.sh 会生成 .env，例如：

    FINDMY_API_TOKEN=自动生成的随机Token
    FINDMY_CORS_ORIGINS=*
    FINDMY_REFRESH_SECONDS=300
    FINDMY_MAX_ALIGNMENT_DAYS=7
    FINDMY_HOST=127.0.0.1
    FINDMY_PORT=18081

生产环境建议把 FINDMY_CORS_ORIGINS=* 改成你的前端域名。多个域名使用英文逗号分隔，例如：

    FINDMY_CORS_ORIGINS=https://a.example.com,https://b.example.com

### 5. 启动

    ./start.sh

测试：

    curl http://127.0.0.1:18081/

正常：

    {"code":0,"msg":"FindMy API Running"}

## API

### 查询缓存位置

GET /api/findmy

Query Token：

    curl "http://127.0.0.1:18081/api/findmy?token=YOUR_TOKEN"

推荐 Bearer Token：

    curl -H "Authorization: Bearer YOUR_TOKEN" http://127.0.0.1:18081/api/findmy

### 手动触发刷新

POST /api/findmy/refresh

    curl -X POST -H "Authorization: Bearer YOUR_TOKEN" http://127.0.0.1:18081/api/findmy/refresh

后台刷新是异步的。接口返回“已开始刷新”后，稍等几秒再次查询 /api/findmy。

## 宝塔 Supervisor

推荐不要直接在终端长期运行 Uvicorn。

运行目录：

    /www/wwwroot/findmy-api

启动命令：

    /www/wwwroot/findmy-api/start.sh

进程数：1

建议开启自动启动和异常自动重启。

如果出现 address already in use：

    ss -lntp | grep 18081

确保只有一个 Uvicorn 实例监听该端口。

## Nginx 反向代理

代理目标：

    http://127.0.0.1:18081

示例：

    location / {
        proxy_pass http://127.0.0.1:18081;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 10s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
    }

建议 Uvicorn 始终只监听 127.0.0.1:18081，不要直接暴露到公网。

## 项目结构

    findmy-api/
    ├── app.py
    ├── install.sh
    ├── start.sh
    ├── requirements.txt
    ├── .env.example
    ├── .gitignore
    ├── LICENSE
    ├── README.md
    ├── devices/
    │   └── .gitkeep
    └── logs/
        └── .gitkeep

运行后本地还会出现 account.json、ani_libs.bin、cache.json、.env、devices/*.json、venv/，这些都不应该提交。

## 致谢

- FindMy.py: https://github.com/malmeloo/FindMy.py

## License

MIT
