#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="python3.12"
PYTHON_FULL_VERSION="${PYTHON_FULL_VERSION:-3.12.12}"
VENV_DIR="${APP_DIR}/venv"
CN_PYPI="${CN_PYPI:-https://pypi.tuna.tsinghua.edu.cn/simple}"
OFFICIAL_PYPI="https://pypi.org/simple"

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_root_if_installing() {
    if [ "${EUID}" -ne 0 ]; then
        echo "需要安装系统依赖，请使用 root 运行 install.sh"
        exit 1
    fi
}

install_build_deps() {
    require_root_if_installing

    if command_exists dnf; then
        dnf install -y             gcc gcc-c++ make curl wget tar gzip ca-certificates             openssl-devel bzip2-devel libffi-devel zlib-devel             xz-devel readline-devel sqlite-devel ncurses-devel             tk-devel gdbm-devel || true
    elif command_exists yum; then
        yum install -y             gcc gcc-c++ make curl wget tar gzip ca-certificates             openssl-devel bzip2-devel libffi-devel zlib-devel             xz-devel readline-devel sqlite-devel ncurses-devel             tk-devel gdbm-devel || true
    elif command_exists apt-get; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y             build-essential curl wget ca-certificates             libssl-dev zlib1g-dev libbz2-dev libreadline-dev             libsqlite3-dev libffi-dev liblzma-dev libncursesw5-dev             tk-dev uuid-dev
    else
        echo "不支持的包管理器，仅支持 dnf / yum / apt-get"
        exit 1
    fi
}

install_python_source() {
    install_build_deps

    local build_dir="/tmp/findmy-python312-build"
    local tar_name="Python-${PYTHON_FULL_VERSION}.tgz"
    local cn_url="https://mirrors.huaweicloud.com/python/${PYTHON_FULL_VERSION}/${tar_name}"
    local official_url="https://www.python.org/ftp/python/${PYTHON_FULL_VERSION}/${tar_name}"

    rm -rf "${build_dir}"
    mkdir -p "${build_dir}"
    cd "${build_dir}"

    echo "正在下载 Python ${PYTHON_FULL_VERSION}..."

    if command_exists curl; then
        if ! curl -fL --retry 3 --connect-timeout 15 -o "${tar_name}" "${cn_url}"; then
            echo "国内镜像失败，切换 Python 官方源..."
            curl -fL --retry 3 --connect-timeout 15 -o "${tar_name}" "${official_url}"
        fi
    else
        if ! wget -O "${tar_name}" "${cn_url}"; then
            wget -O "${tar_name}" "${official_url}"
        fi
    fi

    tar -zxf "${tar_name}"
    cd "Python-${PYTHON_FULL_VERSION}"

    ./configure --prefix=/usr/local --with-ensurepip=install

    local cpu_count
    cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"

    make -j"${cpu_count}"
    make altinstall

    rm -rf "${build_dir}"
}

install_python312() {
    if command_exists "${PYTHON_BIN}"; then
        "${PYTHON_BIN}" --version
        return
    fi

    require_root_if_installing

    echo "未找到 Python 3.12，尝试从系统仓库安装..."

    if command_exists dnf; then
        dnf install -y python3.12 python3.12-pip python3.12-devel 2>/dev/null || true
    elif command_exists yum; then
        yum install -y python3.12 python3.12-pip python3.12-devel 2>/dev/null || true
    elif command_exists apt-get; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y             python3.12 python3.12-venv python3.12-dev 2>/dev/null || true
    fi

    if ! command_exists "${PYTHON_BIN}"; then
        echo "系统仓库没有 Python 3.12，开始源码安装..."
        install_python_source
    fi

    if ! command_exists "${PYTHON_BIN}"; then
        echo "Python 3.12 安装失败"
        exit 1
    fi
}

cd "${APP_DIR}"

echo "=============================================="
echo " FindMy API 一键安装"
echo " 项目目录：${APP_DIR}"
echo "=============================================="

install_python312

echo "[1/6] 创建虚拟环境"

if [ ! -x "${VENV_DIR}/bin/python" ]; then
    rm -rf "${VENV_DIR}"

    if ! "${PYTHON_BIN}" -m venv "${VENV_DIR}"; then
        "${PYTHON_BIN}" -m ensurepip --upgrade || true
        "${PYTHON_BIN}" -m venv "${VENV_DIR}"
    fi
fi

VENV_PYTHON="${VENV_DIR}/bin/python"

echo "[2/6] 初始化 pip"

"${VENV_PYTHON}" -m ensurepip --upgrade || true
"${VENV_PYTHON}" -m pip install -i "${CN_PYPI}" --upgrade pip setuptools wheel || "${VENV_PYTHON}" -m pip install -i "${OFFICIAL_PYPI}" --upgrade pip setuptools wheel

echo "[3/6] 安装依赖"

if ! "${VENV_PYTHON}" -m pip install -i "${CN_PYPI}" --no-cache-dir -r "${APP_DIR}/requirements.txt"; then
    echo "国内 PyPI 镜像安装失败，切换官方 PyPI..."
    "${VENV_PYTHON}" -m pip install -i "${OFFICIAL_PYPI}" --no-cache-dir -r "${APP_DIR}/requirements.txt"
fi

echo "[4/6] 初始化目录"

mkdir -p "${APP_DIR}/devices"
mkdir -p "${APP_DIR}/logs"

echo "[5/6] 生成配置"

if [ ! -f "${APP_DIR}/.env" ]; then
    API_TOKEN="$("${VENV_PYTHON}" -c 'import secrets; print(secrets.token_urlsafe(32))')"

    cat > "${APP_DIR}/.env" <<EOF
FINDMY_API_TOKEN=${API_TOKEN}
FINDMY_CORS_ORIGINS=*
FINDMY_REFRESH_SECONDS=300
FINDMY_MAX_ALIGNMENT_DAYS=7
FINDMY_HOST=127.0.0.1
FINDMY_PORT=18081
EOF

    chmod 600 "${APP_DIR}/.env"

    echo
    echo "已生成 API Token："
    echo "${API_TOKEN}"
    echo
    echo "Token 已保存到：${APP_DIR}/.env"
else
    echo ".env 已存在，不覆盖"
fi

chmod +x "${APP_DIR}/start.sh"

if [ -f "${APP_DIR}/account.json" ]; then
    chmod 600 "${APP_DIR}/account.json"
else
    echo "提示：尚未发现 account.json"
fi

if [ -f "${APP_DIR}/ani_libs.bin" ]; then
    chmod 600 "${APP_DIR}/ani_libs.bin"
fi

if compgen -G "${APP_DIR}/devices/*.json" > /dev/null; then
    chmod 600 "${APP_DIR}"/devices/*.json
else
    echo "提示：devices/ 目录暂时没有物品 JSON"
fi

echo "[6/6] 验证"

"${VENV_PYTHON}" -m py_compile "${APP_DIR}/app.py"

"${VENV_PYTHON}" - <<'PY'
import findmy
import fastapi
import uvicorn
print("FindMy OK")
print("FastAPI OK")
print("Uvicorn OK")
PY

echo
echo "=============================================="
echo " 安装完成"
echo "=============================================="
echo "启动："
echo "  ${APP_DIR}/start.sh"
echo
echo "测试："
echo "  curl http://127.0.0.1:18081/"
echo
echo "Supervisor 启动命令："
echo "  ${APP_DIR}/start.sh"
