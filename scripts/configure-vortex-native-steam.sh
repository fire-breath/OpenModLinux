#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Map the native Steam root directly into a Vortex Wine/UMU prefix.
#
# Windows view:
#   C:\SteamLibrary -> native Linux Steam root
#   C:\SteamLibrary\steamapps\vortex-userdata
#
# Keeping Vortex staging and the managed Steam game on the same Linux
# filesystem allows Hardlink Deployment to work without EXDEV errors.

PREFIX="${1:-}"
NATIVE_STEAM="${NATIVE_STEAM_ROOT:-$HOME/.local/share/Steam}"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ -n "$PREFIX" ]] || die "Usage: $0 PREFIX"
[[ $EUID -ne 0 ]] || die "Do not run this script with sudo."
[[ -d "$NATIVE_STEAM/steamapps" ]] || die "Native Steam root not found: $NATIVE_STEAM"

if [[ -d "$PREFIX/drive_c" ]]; then
    DRIVE_C="$PREFIX/drive_c"
elif [[ -d "$PREFIX/pfx/drive_c" ]]; then
    DRIVE_C="$PREFIX/pfx/drive_c"
    [[ -e "$PREFIX/drive_c" ]] || ln -s "pfx/drive_c" "$PREFIX/drive_c"
else
    die "drive_c was not found in prefix: $PREFIX"
fi

TS="$(date +%Y%m%d_%H%M%S)"
MAPPING="$DRIVE_C/SteamLibrary"
USERDATA="$NATIVE_STEAM/steamapps/vortex-userdata"

backup_name() {
    local source="$1"
    local candidate="${source}.backup_${TS}"
    local index=1
    while [[ -e "$candidate" || -L "$candidate" ]]; do
        candidate="${source}.backup_${TS}_${index}"
        ((index++))
    done
    printf '%s\n' "$candidate"
}

copy_merge() {
    local source="$1"
    local target="$2"
    mkdir -p "$target"

    if command -v rsync >/dev/null 2>&1; then
        rsync -a --ignore-existing -- "$source"/ "$target"/
    else
        cp -an --reflink=auto "$source"/. "$target"/
    fi
}

move_or_merge() {
    local source="$1"
    local target="$2"

    [[ -e "$source" || -L "$source" ]] || return 0
    [[ "$(realpath -m "$source")" != "$(realpath -m "$target")" ]] || return 0

    if [[ -L "$source" ]]; then
        local resolved
        resolved="$(readlink -f "$source" 2>/dev/null || true)"
        [[ -n "$resolved" && -d "$resolved" ]] && copy_merge "$resolved" "$target"
        rm -f "$source"
        return 0
    fi

    if [[ -d "$source" ]]; then
        copy_merge "$source" "$target"
        mv "$source" "$(backup_name "$source")"
    else
        mv "$source" "$(backup_name "$source")"
    fi
}

if [[ -L "$MAPPING" ]]; then
    if [[ "$(readlink -f "$MAPPING")" != "$(realpath "$NATIVE_STEAM")" ]]; then
        mv "$MAPPING" "$(backup_name "$MAPPING")"
        ln -s "$NATIVE_STEAM" "$MAPPING"
    fi
elif [[ -e "$MAPPING" ]]; then
    mv "$MAPPING" "$(backup_name "$MAPPING")"
    ln -s "$NATIVE_STEAM" "$MAPPING"
else
    ln -s "$NATIVE_STEAM" "$MAPPING"
fi

mkdir -p "$USERDATA"

LEGACY_USERDATA=(
    "$DRIVE_C/Program Files (x86)/Steam/steamapps/vortex-userdata"
    "$DRIVE_C/users/steamuser/AppData/Roaming/Vortex"
)

while IFS= read -r -d '' home_dir; do
    LEGACY_USERDATA+=("$home_dir/AppData/Roaming/Vortex")
done < <(find "$DRIVE_C/users" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

for source in "${LEGACY_USERDATA[@]}"; do
    move_or_merge "$source" "$USERDATA"
done

DOWNLOADS=""
if command -v xdg-user-dir >/dev/null 2>&1; then
    DOWNLOADS="$(xdg-user-dir DOWNLOAD 2>/dev/null || true)"
fi
[[ -n "$DOWNLOADS" && "$DOWNLOADS" != "$HOME" ]] || DOWNLOADS="$HOME/Загрузки"
mkdir -p "$DOWNLOADS"

if [[ -L "$USERDATA/downloads" ]]; then
    rm -f "$USERDATA/downloads"
elif [[ -d "$USERDATA/downloads" ]]; then
    copy_merge "$USERDATA/downloads" "$DOWNLOADS"
    mv "$USERDATA/downloads" "$(backup_name "$USERDATA/downloads")"
elif [[ -e "$USERDATA/downloads" ]]; then
    mv "$USERDATA/downloads" "$(backup_name "$USERDATA/downloads")"
fi
ln -s "$DOWNLOADS" "$USERDATA/downloads"

printf 'C:\\SteamLibrary -> %s\n' "$(readlink -f "$MAPPING")"
printf 'Vortex userdata: C:\\SteamLibrary\\steamapps\\vortex-userdata\n'
printf 'Downloads: %s\n' "$DOWNLOADS"

SKYRIM="$NATIVE_STEAM/steamapps/common/Skyrim Special Edition"
STAGING="$USERDATA/skyrimse/mods"
if [[ -d "$SKYRIM" ]]; then
    mkdir -p "$STAGING" "$SKYRIM/Data"
    if [[ "$(stat -c '%d' "$STAGING")" != "$(stat -c '%d' "$SKYRIM/Data")" ]]; then
        die "Vortex staging and Skyrim Data are still on different devices."
    fi

    source_test="$STAGING/.openmodlinux-hardlink-${TS}"
    target_test="$SKYRIM/Data/.openmodlinux-hardlink-${TS}"
    trap 'rm -f "$source_test" "$target_test"' EXIT
    printf 'OpenModLinux hardlink test\n' >"$source_test"
    ln "$source_test" "$target_test" || die "Hardlink test failed."
    rm -f "$source_test" "$target_test"
    trap - EXIT
    printf 'Hardlink deployment test: PASS\n'
fi
