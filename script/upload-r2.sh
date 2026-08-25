#!/bin/bash
# =============================================================================
# upload-r2.sh — 把公证后的 DMG 传到 Cloudflare R2
# =============================================================================
#
# 稳定公开地址（最终版会覆盖 latest）：
#   https://download.onecat.dev/Light-Stats.dmg
# 版本固定地址：
#   https://download.onecat.dev/Light-Stats-<version>.dmg
#
# 预发布（tag 含连字符，如 v1.9.1-beta.1）只上传版本对象，不覆盖 latest。
# 应用内自动更新仍走 GitHub Releases；R2 只服务站点/分享用的安装包链接。
#
# 环境变量：
#   R2_ACCOUNT_ID        Cloudflare 账号 ID（必填）
#   R2_ACCESS_KEY_ID     R2 S3 API token（必填）
#   R2_SECRET_ACCESS_KEY R2 S3 API secret（必填）
#   R2_BUCKET            默认 light-stats
#   VERSION              无 v 前缀的版本号，如 1.9.0（可用参数 2）
#   PRERELEASE           true/false（可用参数 3）
#
# 用法：
#   ./script/upload-r2.sh "build/output/Light Stats-1.9.0.dmg" 1.9.0 false
# =============================================================================

set -euo pipefail
cd "$(dirname "$0")/.."

DMG_PATH="${1:-}"
VERSION="${2:-${VERSION:-}}"
PRERELEASE="${3:-${PRERELEASE:-false}}"
R2_BUCKET="${R2_BUCKET:-light-stats}"

if [ -z "$DMG_PATH" ] || [ -z "$VERSION" ]; then
    echo "usage: $0 <dmg-path> <version> [prerelease]" >&2
    exit 1
fi
if [ ! -f "$DMG_PATH" ]; then
    echo "error: DMG not found: $DMG_PATH" >&2
    exit 1
fi
for name in R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY; do
    if [ -z "${!name:-}" ]; then
        echo "error: missing $name" >&2
        exit 1
    fi
done

python3 - "$DMG_PATH" "$VERSION" "$PRERELEASE" "$R2_BUCKET" <<'PY'
import hashlib
import hmac
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

dmg_path = Path(sys.argv[1])
version = sys.argv[2]
prerelease = sys.argv[3].lower() in {"1", "true", "yes"}
bucket = sys.argv[4]
account = os.environ["R2_ACCOUNT_ID"]
access = os.environ["R2_ACCESS_KEY_ID"]
secret = os.environ["R2_SECRET_ACCESS_KEY"]
host = f"{account}.r2.cloudflarestorage.com"
region = "auto"
service = "s3"
body = dmg_path.read_bytes()
digest = hashlib.sha256(body).hexdigest()

def sign(key: bytes, msg: str) -> bytes:
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()

def put_object(key, data, content_type, cache_control, content_disposition=None):
    now = datetime.now(timezone.utc)
    amzdate = now.strftime("%Y%m%dT%H%M%SZ")
    datestamp = now.strftime("%Y%m%d")
    payload_hash = hashlib.sha256(data).hexdigest()
    headers = {
        "cache-control": cache_control,
        "content-type": content_type,
        "host": host,
        "x-amz-content-sha256": payload_hash,
        "x-amz-date": amzdate,
    }
    if content_disposition:
        headers["content-disposition"] = content_disposition
    signed_headers = ";".join(sorted(headers))
    canonical_headers = "".join(f"{name}:{headers[name]}\n" for name in sorted(headers))
    canonical_uri = f"/{bucket}/{key}"
    canonical_request = "\n".join([
        "PUT",
        canonical_uri,
        "",
        canonical_headers,
        signed_headers,
        payload_hash,
    ])
    algorithm = "AWS4-HMAC-SHA256"
    credential_scope = f"{datestamp}/{region}/{service}/aws4_request"
    string_to_sign = "\n".join([
        algorithm,
        amzdate,
        credential_scope,
        hashlib.sha256(canonical_request.encode("utf-8")).hexdigest(),
    ])
    k_date = sign(f"AWS4{secret}".encode("utf-8"), datestamp)
    k_region = hmac.new(k_date, region.encode("utf-8"), hashlib.sha256).digest()
    k_service = hmac.new(k_region, service.encode("utf-8"), hashlib.sha256).digest()
    k_signing = hmac.new(k_service, b"aws4_request", hashlib.sha256).digest()
    signature = hmac.new(k_signing, string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()
    authorization = (
        f"{algorithm} Credential={access}/{credential_scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )
    request = Request(f"https://{host}{canonical_uri}", data=data, method="PUT")
    for name, value in headers.items():
        if name != "host":
            request.add_header(name, value)
    request.add_header("Authorization", authorization)
    with urlopen(request, timeout=120) as response:
        if response.status not in {200, 201}:
            raise SystemExit(f"R2 PUT {key} failed: HTTP {response.status}")
    print(f"uploaded s3://{bucket}/{key} ({len(data)} bytes)")

versioned_name = f"Light-Stats-{version}.dmg"
put_object(
    versioned_name,
    body,
    "application/x-apple-diskimage",
    "public, max-age=31536000, immutable",
    f'attachment; filename="Light Stats-{version}.dmg"',
)
put_object(
    f"{versioned_name}.sha256",
    f"{digest}  {versioned_name}\n".encode("utf-8"),
    "text/plain; charset=utf-8",
    "public, max-age=31536000, immutable",
    None,
)

if not prerelease:
    put_object(
        "Light-Stats.dmg",
        body,
        "application/x-apple-diskimage",
        "public, no-cache, must-revalidate",
        'attachment; filename="Light Stats.dmg"',
    )
    sums = f"{digest}  Light-Stats.dmg\n{digest}  {versioned_name}\n"
    put_object(
        "SHA256SUMS.txt",
        sums.encode("utf-8"),
        "text/plain; charset=utf-8",
        "public, no-cache, must-revalidate",
        None,
    )
    print(f"stable URL: https://download.onecat.dev/Light-Stats.dmg")
else:
    print("prerelease: left Light-Stats.dmg unchanged")

print(f"versioned URL: https://download.onecat.dev/{versioned_name}")
PY
