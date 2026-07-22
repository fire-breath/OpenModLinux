#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

APP_NAME="wine-prefix-integration"
CONFIG_PATH="$HOME/.config/$APP_NAME/roots.conf"

resolve_xdg_dir() {
    local kind="$1" ru_name="$2" en_name="$3" result=""
    if command -v xdg-user-dir >/dev/null 2>&1; then
        result="$(xdg-user-dir "$kind" 2>/dev/null || true)"
    fi
    if [[ -z "$result" || "$result" == "$HOME" ]]; then
        if [[ -d "$HOME/$ru_name" ]]; then
            result="$HOME/$ru_name"
        else
            result="$HOME/$en_name"
        fi
    fi
    mkdir -p "$result"
    realpath -m "$result"
}

DOCUMENTS_TARGET="$(resolve_xdg_dir DOCUMENTS Документы Documents)"
DOWNLOADS_TARGET="$(resolve_xdg_dir DOWNLOAD Загрузки Downloads)"

backup_name() {
    local path="$1"
    printf '%s.before-shared-folders_%s\n' "$path" "$(date +%Y%m%d_%H%M%S)"
}

is_empty_dir() {
    [[ -d "$1" ]] || return 1
    ! find "$1" -mindepth 1 -print -quit 2>/dev/null | grep -q .
}

copy_merge() {
    local source="$1" target="$2"
    mkdir -p "$target"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --ignore-existing -- "$source"/ "$target"/
    else
        cp -an --reflink=auto "$source"/. "$target"/
    fi
}

redirect_shared() {
    local source="$1" target="$2"
    mkdir -p "$(dirname "$source")" "$target"

    if [[ -L "$source" ]]; then
        [[ "$(readlink -f "$source" 2>/dev/null || true)" == "$(realpath -m "$target")" ]] && return 0
        rm -f "$source"
    elif [[ -d "$source" ]]; then
        if is_empty_dir "$source"; then
            rmdir "$source"
        else
            copy_merge "$source" "$target"
            mv "$source" "$(backup_name "$source")"
        fi
    elif [[ -e "$source" ]]; then
        mv "$source" "$(backup_name "$source")"
    fi

    ln -s "$target" "$source"
}

process_users() {
    local users="$1"
    [[ -d "$users" ]] || return 0

    local profile name
    while IFS= read -r -d '' profile; do
        name="$(basename "$profile")"
        case "$name" in
            Public|"All Users"|Default|"Default User"|defaultuser0) continue ;;
        esac

        redirect_shared "$profile/Documents" "$DOCUMENTS_TARGET"
        redirect_shared "$profile/Downloads" "$DOWNLOADS_TARGET"

        if [[ ! -e "$profile/My Documents" && ! -L "$profile/My Documents" ]]; then
            ln -s "Documents" "$profile/My Documents"
        fi

        # Staging Vortex */mods намеренно не изменяется.
    done < <(find "$users" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
}

ROOTS=(
    "$HOME/.wine"
    "$HOME/Games"
    "$HOME/.local/share/lutris"
    "$HOME/.local/share/bottles/bottles"
    "$HOME/.local/share/Steam/steamapps/compatdata"
    "$HOME/.steam/steam/steamapps/compatdata"
    "$HOME/.var/app/net.lutris.Lutris/data/lutris"
    "$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles"
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/compatdata"
    "$HOME/Games/Heroic/Prefixes"
    "/mnt/DataStore/Games"
    "/mnt/DataStore/games"
)

if [[ -f "$CONFIG_PATH" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        [[ -n "${line//[[:space:]]/}" ]] && ROOTS+=("${line/#\~/$HOME}")
    done <"$CONFIG_PATH"
fi

declare -A seen=()
for root in "${ROOTS[@]}"; do
    [[ -d "$root" ]] || continue

    while IFS= read -r -d '' users; do
        canonical="$(realpath -m "$users")"
        [[ -n "${seen[$canonical]:-}" ]] && continue
        seen["$canonical"]=1
        process_users "$users"
    done < <(
        find "$root" -xdev -maxdepth 12 -type d \
            \( -path '*/drive_c/users' -o -path '*/pfx/drive_c/users' \) \
            -print0 2>/dev/null
    )
done
