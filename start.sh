#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${APP_DIR}/venv"

cd "${APP_DIR}"

if [ ! -x "${VENV_DIR}/bin/python" ]; then
    echo "未找到虚拟环境：${VENV_DIR}"
    echo "请先执行：./install.sh"
    exit 1
fi

if [ -f "${APP_DIR}/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "${APP_DIR}/.env"
    set +a
fi

exec "${VENV_DIR}/bin/python"     -m uvicorn app:app     --app-dir "${APP_DIR}"     --host "${FINDMY_HOST:-127.0.0.1}"     --port "${FINDMY_PORT:-18081}"
