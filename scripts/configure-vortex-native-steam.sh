#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PREFIX="${1:-}"
NATIVE_STEAM="${NATIVE_STEAM_ROOT:-$HOME/.local/share/Steam}"

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
    echo "drive_c not found: $PREFIX" >&2
    exit 1
fi

[[ -d "$NATIVE_STEAM/steamapps" ]] || {
    echo "Native Steam root not found: $NATIVE_STEAM" >&2
    exit 1
}

MAPPING="$DRIVE_C/SteamLibrary"

if [[ -L "$MAPPING" ]]; then
    if [[ "$(readlink -f "$MAPPING")" != "$(realpath "$NATIVE_STEAM")" ]]; then
        rm -f "$MAPPING"
        ln -s "$NATIVE_STEAM" "$MAPPING"
    fi
elif [[ ! -e "$MAPPING" ]]; then
    ln -s "$NATIVE_STEAM" "$MAPPING"
else
    echo "C:\\SteamLibrary already exists and is not a symlink: $MAPPING" >&2
    exit 1
fi

USERDATA="$MAPPING/steamapps/vortex-userdata"
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

echo "Created C:\\SteamLibrary -> $NATIVE_STEAM"
echo "Vortex USERDATA: C:\\SteamLibrary\\steamapps\\vortex-userdata"
