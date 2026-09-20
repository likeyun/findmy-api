import json
import os
import threading
import time
from datetime import datetime, timezone, timedelta
from pathlib import Path
from urllib.parse import quote

from fastapi import FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from findmy import AppleAccount, FindMyAccessory

BASE = Path(__file__).resolve().parent
DEVICE_DIR = BASE / "devices"
ACCOUNT_FILE = BASE / "account.json"
ANISETTE_FILE = BASE / "ani_libs.bin"
CACHE_FILE = BASE / "cache.json"

API_TOKEN = os.getenv("FINDMY_API_TOKEN", "").strip()
REFRESH_SECONDS = int(os.getenv("FINDMY_REFRESH_SECONDS", "300"))
MAX_ALIGNMENT_DAYS = int(os.getenv("FINDMY_MAX_ALIGNMENT_DAYS", "7"))

cors_raw = os.getenv("FINDMY_CORS_ORIGINS", "*").strip()
CORS_ORIGINS = [x.strip() for x in cors_raw.split(",") if x.strip()] or ["*"]

app = FastAPI(title="FindMy API", docs_url=None, redoc_url=None)

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

refresh_lock = threading.Lock()
stop_event = threading.Event()


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(
        json.dumps(data, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    tmp.replace(path)


def close_account(account):
    try:
        account._evt_loop.run_until_complete(account.close())
    except Exception:
        pass


def verify_token(
    token: str | None = Query(default=None),
    authorization: str | None = Header(default=None),
):
    if not API_TOKEN:
        raise HTTPException(
            status_code=503,
            detail="FINDMY_API_TOKEN is not configured",
        )

    if token == API_TOKEN:
        return

    if authorization == f"Bearer {API_TOKEN}":
        return

    raise HTTPException(status_code=401, detail="Unauthorized")


def get_cache():
    if not CACHE_FILE.exists():
        return {
            "code": 0,
            "msg": "正在获取位置，请稍后刷新",
            "update_time": None,
            "count": 0,
            "data": [],
        }

    try:
        return read_json(CACHE_FILE)
    except Exception as exc:
        return {
            "code": 500,
            "msg": "缓存读取失败",
            "error": str(exc),
            "update_time": None,
            "count": 0,
            "data": [],
        }


def refresh_locations():
    if not refresh_lock.acquire(blocking=False):
        return

    account = None

    try:
        if not ACCOUNT_FILE.exists():
            raise RuntimeError(f"找不到账号文件：{ACCOUNT_FILE}")

        DEVICE_DIR.mkdir(parents=True, exist_ok=True)

        # 不主动检查 ani_libs.bin。
        # 文件不存在时，由 FindMy.py 的 Local Anisette 初始化逻辑处理。
        account = AppleAccount.from_json(
            read_json(ACCOUNT_FILE),
            anisette_libs_path=ANISETTE_FILE,
        )

        now = datetime.now(timezone.utc)
        result = []
        success = 0
        no_location = 0
        failed = 0

        for path in sorted(DEVICE_DIR.glob("*.json")):
            try:
                raw = read_json(path)

                if raw.get("type") != "accessory":
                    continue

                name = raw.get("name") or path.stem
                model = raw.get("model") or "Unknown"
                alignment = raw.get("alignment_date")

                if not alignment:
                    continue

                alignment_time = datetime.fromisoformat(alignment)

                if alignment_time.tzinfo is None:
                    alignment_time = alignment_time.replace(tzinfo=timezone.utc)

                age = now - alignment_time.astimezone(timezone.utc)

                if age > timedelta(days=MAX_ALIGNMENT_DAYS):
                    continue

                item = FindMyAccessory.from_json(raw)
                started = time.time()

                try:
                    location = account.fetch_location(item)
                except Exception as exc:
                    failed += 1
                    result.append(
                        {
                            "name": name,
                            "model": model,
                            "status": "error",
                            "error": f"{type(exc).__name__}: {exc}",
                        }
                    )
                    continue

                elapsed = round(time.time() - started, 2)

                # 保存 FindMy.py 更新后的 alignment 状态。
                write_json(path, item.to_json())

                if location is None:
                    no_location += 1
                    result.append(
                        {
                            "name": name,
                            "model": model,
                            "status": "no_location",
                            "elapsed": elapsed,
                        }
                    )
                    continue

                success += 1

                latitude = location.latitude
                longitude = location.longitude
                status_value = getattr(location.status, "value", location.status)

                result.append(
                    {
                        "name": name,
                        "model": model,
                        "status": "success",
                        "latitude": latitude,
                        "longitude": longitude,
                        "accuracy": location.horizontal_accuracy,
                        "location_time": location.timestamp.isoformat(),
                        "device_status": status_value,
                        "elapsed": elapsed,
                        "map_url": (
                            "https://uri.amap.com/marker"
                            f"?position={longitude},{latitude}"
                            f"&name={quote(name)}"
                        ),
                    }
                )

            except Exception as exc:
                failed += 1
                result.append(
                    {
                        "name": path.stem,
                        "status": "error",
                        "error": f"{type(exc).__name__}: {exc}",
                    }
                )

        write_json(ACCOUNT_FILE, account.to_json())

        cache = {
            "code": 0,
            "msg": "获取成功",
            "update_time": datetime.now().astimezone().isoformat(),
            "count": len(result),
            "success": success,
            "no_location": no_location,
            "failed": failed,
            "data": result,
        }

        write_json(CACHE_FILE, cache)

    except Exception as exc:
        old_cache = get_cache()
        old_cache["last_error"] = f"{type(exc).__name__}: {exc}"
        old_cache["last_error_time"] = datetime.now().astimezone().isoformat()

        try:
            write_json(CACHE_FILE, old_cache)
        except Exception:
            pass

    finally:
        if account is not None:
            close_account(account)

        refresh_lock.release()


def refresh_worker():
    while not stop_event.is_set():
        refresh_locations()
        stop_event.wait(REFRESH_SECONDS)


@app.on_event("startup")
def startup():
    thread = threading.Thread(
        target=refresh_worker,
        daemon=True,
        name="findmy-refresh",
    )
    thread.start()


@app.on_event("shutdown")
def shutdown():
    stop_event.set()


@app.get("/")
def index():
    return {
        "code": 0,
        "msg": "FindMy API Running",
    }


@app.get("/api/findmy")
def findmy_api(
    token: str | None = Query(default=None),
    authorization: str | None = Header(default=None),
):
    verify_token(token, authorization)
    return get_cache()


@app.post("/api/findmy/refresh")
def refresh_api(
    token: str | None = Query(default=None),
    authorization: str | None = Header(default=None),
):
    verify_token(token, authorization)

    if refresh_lock.locked():
        return {
            "code": 1,
            "msg": "正在刷新中",
        }

    threading.Thread(
        target=refresh_locations,
        daemon=True,
        name="findmy-manual-refresh",
    ).start()

    return {
        "code": 0,
        "msg": "已开始刷新",
    }
