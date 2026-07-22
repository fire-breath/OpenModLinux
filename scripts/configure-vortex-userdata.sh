#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PREFIX="${1:-}"
[[ -n "$PREFIX" ]] || {
    echo "Usage: $0 PREFIX" >&2
    exit 2
}

if [[ -d "$PREFIX/drive_c" ]]; then
    DRIVE_C="$PREFIX/drive_c"
elif [[ -d "$PREFIX/pfx/drive_c" ]]; then
    DRIVE_C="$PREFIX/pfx/drive_c"
    [[ -e "$PREFIX/drive_c" ]] || ln -s "pfx/drive_c" "$PREFIX/drive_c"
else
    echo "drive_c not found in prefix: $PREFIX" >&2
    exit 1
fi

STEAM_ROOT="$DRIVE_C/Program Files (x86)/Steam"
USERDATA="$STEAM_ROOT/steamapps/vortex-userdata"

[[ -e "$STEAM_ROOT" ]] || {
    echo "Mapped Steam root not found: $STEAM_ROOT" >&2
    exit 1
}

mkdir -p "$USERDATA"

DOWNLOADS=""
if command -v xdg-user-dir >/dev/null 2>&1; then
    DOWNLOADS="$(xdg-user-dir DOWNLOAD 2>/dev/null || true)"
fi
[[ -n "$DOWNLOADS" && "$DOWNLOADS" != "$HOME" ]] || DOWNLOADS="$HOME/Загрузки"
mkdir -p "$DOWNLOADS"

if [[ -L "$USERDATA/downloads" ]]; then
    rm -f "$USERDATA/downloads"
elif [[ -d "$USERDATA/downloads" ]]; then
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --ignore-existing "$USERDATA/downloads"/ "$DOWNLOADS"/
    else
        cp -an --reflink=auto "$USERDATA/downloads"/. "$DOWNLOADS"/
    fi
    mv "$USERDATA/downloads" \
       "$USERDATA/downloads.backup_$(date +%Y%m%d_%H%M%S)"
fi

ln -s "$DOWNLOADS" "$USERDATA/downloads"
echo "Vortex USERDATA prepared: $USERDATA"
