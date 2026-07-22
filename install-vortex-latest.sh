#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

command -v lutris >/dev/null 2>&1 || {
    echo "Lutris не установлен." >&2
    exit 1
}

exec lutris -i "$ROOT/lutris/vortex.yml"
