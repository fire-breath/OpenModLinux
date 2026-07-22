#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

DESTINATION="${1:-}"
[[ -n "$DESTINATION" ]] || {
    echo "Usage: $0 DESTINATION" >&2
    exit 2
}

for cmd in python3 curl sha256sum; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Required command not found: $cmd" >&2
        exit 1
    }
done

mkdir -p "$(dirname "$DESTINATION")"
TMP_META="$(mktemp)"
TMP_FILE="${DESTINATION}.part"
trap 'rm -f "$TMP_META" "$TMP_FILE"' EXIT

python3 - "$TMP_META" <<'PY'
import json
import re
import sys
import urllib.request

out = sys.argv[1]
api = "https://api.github.com/repos/Nexus-Mods/Vortex/releases/latest"
req = urllib.request.Request(
    api,
    headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "OpenModLinux-Vortex-Installer",
        "X-GitHub-Api-Version": "2022-11-28",
    },
)

with urllib.request.urlopen(req, timeout=45) as response:
    release = json.load(response)

if release.get("draft") or release.get("prerelease"):
    raise SystemExit("GitHub latest release is not a stable release")

assets = release.get("assets") or []
candidates = []
for asset in assets:
    name = asset.get("name") or ""
    url = asset.get("browser_download_url") or ""
    if re.search(r"(?i)^vortex[-_ ]?setup[-_ ].*\.exe$", name):
        candidates.append((name, url, int(asset.get("size") or 0)))

if not candidates:
    for asset in assets:
        name = asset.get("name") or ""
        url = asset.get("browser_download_url") or ""
        if name.lower().endswith(".exe") and "setup" in name.lower():
            candidates.append((name, url, int(asset.get("size") or 0)))

if not candidates:
    raise SystemExit("No Vortex setup EXE was found in the latest official release")

name, url, size = sorted(candidates, key=lambda item: item[2], reverse=True)[0]
data = {
    "tag": release.get("tag_name") or "",
    "version": (release.get("tag_name") or "").lstrip("vV"),
    "name": name,
    "url": url,
    "size": size,
    "html_url": release.get("html_url") or "",
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False)
PY

readarray -t META < <(
    python3 - "$TMP_META" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
for key in ("tag", "version", "name", "url", "size", "html_url"):
    print(data.get(key, ""))
PY
)

TAG="${META[0]}"
ASSET_NAME="${META[2]}"
URL="${META[3]}"
EXPECTED_SIZE="${META[4]}"
RELEASE_PAGE="${META[5]}"

echo "Последний стабильный выпуск Vortex: $TAG"
echo "Файл: $ASSET_NAME"
echo "Источник: $RELEASE_PAGE"

CACHE_META="${DESTINATION}.release.json"
if [[ -f "$DESTINATION" && -f "$CACHE_META" ]]; then
    CACHED_URL="$(python3 - "$CACHE_META" 2>/dev/null <<'PY' || true
import json
import sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        print(json.load(f).get("url", ""))
except Exception:
    pass
PY
)"
    if [[ "$CACHED_URL" == "$URL" ]] && \
       [[ "$(head -c 2 "$DESTINATION" 2>/dev/null || true)" == "MZ" ]]; then
        echo "Актуальный установщик уже находится в кэше:"
        echo "$DESTINATION"
        sha256sum "$DESTINATION"
        exit 0
    fi
fi

rm -f "$TMP_FILE"
curl \
    --fail \
    --location \
    --continue-at - \
    --retry 8 \
    --retry-all-errors \
    --connect-timeout 30 \
    --output "$TMP_FILE" \
    "$URL"

ACTUAL_SIZE="$(stat -c '%s' "$TMP_FILE")"
if [[ "$EXPECTED_SIZE" =~ ^[0-9]+$ ]] && ((EXPECTED_SIZE > 0)) && \
   ((ACTUAL_SIZE != EXPECTED_SIZE)); then
    echo "Размер загруженного файла не совпадает с размером GitHub asset." >&2
    echo "Ожидалось: $EXPECTED_SIZE; получено: $ACTUAL_SIZE" >&2
    exit 1
fi

[[ "$(head -c 2 "$TMP_FILE" 2>/dev/null || true)" == "MZ" ]] || {
    echo "Загруженный файл не похож на Windows EXE." >&2
    exit 1
}

mv -f "$TMP_FILE" "$DESTINATION"
cp -f "$TMP_META" "$CACHE_META"

echo "Vortex загружен:"
echo "$DESTINATION"
sha256sum "$DESTINATION"
