#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

APP_NAME="wine-prefix-integration"
SELF="$(realpath "${BASH_SOURCE[0]}")"
GLOBAL_BIN="$HOME/.local/bin/$APP_NAME"
SYSTEMD_DIR="$HOME/.config/systemd/user"
SERVICE_PATH="$SYSTEMD_DIR/$APP_NAME.service"
TIMER_PATH="$SYSTEMD_DIR/$APP_NAME.timer"
CONFIG_DIR="$HOME/.config/$APP_NAME"
CONFIG_PATH="$CONFIG_DIR/roots.conf"

ONLY_PREFIX=""
INSTALL_GLOBAL=0
UNINSTALL=0

while (($#)); do
    case "$1" in
        --prefix)
            [[ $# -ge 2 ]] || {
                echo "--prefix requires a path" >&2
                exit 2
            }
            ONLY_PREFIX="$2"
            shift 2
            ;;
        --install-global)
            INSTALL_GLOBAL=1
            shift
            ;;
        --uninstall)
            UNINSTALL=1
            shift
            ;;
        -h|--help)
            cat <<'EOF'
Usage:
  wine-prefix-integration.sh
  wine-prefix-integration.sh --prefix PREFIX
  wine-prefix-integration.sh --install-global [--prefix PREFIX]
  wine-prefix-integration.sh --uninstall
EOF
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

resolve_xdg_dir() {
    local kind="$1"
    local fallback_ru="$2"
    local fallback_en="$3"
    local dir=""

    if command -v xdg-user-dir >/dev/null 2>&1; then
        dir="$(xdg-user-dir "$kind" 2>/dev/null || true)"
    fi

    if [[ -z "$dir" || "$dir" == "$HOME" ]]; then
        if [[ -d "$HOME/$fallback_ru" ]]; then
            dir="$HOME/$fallback_ru"
        else
            dir="$HOME/$fallback_en"
        fi
    fi

    mkdir -p "$dir"
    realpath -m "$dir"
}

DOCUMENTS_TARGET="${WINE_DOCUMENTS_TARGET:-$(resolve_xdg_dir DOCUMENTS Документы Documents)}"
DOWNLOADS_TARGET="${WINE_DOWNLOADS_TARGET:-$(resolve_xdg_dir DOWNLOAD Загрузки Downloads)}"

backup_name() {
    local path="$1"
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    local candidate="${path}.before-unified-integration_${ts}"
    local n=1
    while [[ -e "$candidate" || -L "$candidate" ]]; do
        candidate="${path}.before-unified-integration_${ts}_${n}"
        ((n++))
    done
    printf '%s\n' "$candidate"
}

directory_empty() {
    [[ -d "$1" ]] || return 1
    ! find "$1" -mindepth 1 -print -quit 2>/dev/null | grep -q .
}

merge_without_overwrite() {
    local source="$1"
    local target="$2"
    mkdir -p "$target"

    if cp -aln -- "$source"/. "$target"/ 2>/dev/null; then
        return 0
    fi

    cp -an -- "$source"/. "$target"/
}

redirect_directory() {
    local source="$1"
    local target="$2"
    local mode="${3:-merge}"

    mkdir -p "$(dirname "$source")" "$(dirname "$target")"

    if [[ -L "$source" ]]; then
        local resolved
        resolved="$(readlink -f "$source" 2>/dev/null || true)"
        if [[ "$resolved" == "$(realpath -m "$target")" ]]; then
            printf 'OK: %s -> %s\n' "$source" "$target"
            return 0
        fi
        rm -f -- "$source"
    elif [[ -d "$source" ]]; then
        if directory_empty "$source"; then
            rmdir -- "$source"
        elif [[ ! -e "$target" ]] || directory_empty "$target"; then
            if [[ -d "$target" ]] && directory_empty "$target"; then
                rmdir -- "$target"
            fi
            if mv -- "$source" "$target" 2>/dev/null; then
                printf 'Перенесено: %s -> %s\n' "$source" "$target"
            else
                mkdir -p "$target"
                merge_without_overwrite "$source" "$target"
                local backup
                backup="$(backup_name "$source")"
                mv -- "$source" "$backup"
                printf 'Сохранён исходный каталог: %s\n' "$backup"
            fi
        else
            if [[ "$mode" == "merge" ]]; then
                merge_without_overwrite "$source" "$target"
            fi
            local backup
            backup="$(backup_name "$source")"
            mv -- "$source" "$backup"
            printf 'Сохранён исходный каталог: %s\n' "$backup"
        fi
    elif [[ -e "$source" ]]; then
        local backup
        backup="$(backup_name "$source")"
        mv -- "$source" "$backup"
        printf 'Сохранён исходный объект: %s\n' "$backup"
    fi

    mkdir -p "$target"
    ln -s -- "$target" "$source"
    printf 'Создано: %s -> %s\n' "$source" "$target"
}

prefix_drive_c() {
    local prefix="$1"

    if [[ -d "$prefix/drive_c" ]]; then
        printf '%s\n' "$prefix/drive_c"
        return 0
    fi

    if [[ -d "$prefix/pfx/drive_c" ]]; then
        if [[ ! -e "$prefix/drive_c" ]]; then
            ln -s "pfx/drive_c" "$prefix/drive_c"
            printf 'Создана совместимость UMU: %s/drive_c -> pfx/drive_c\n' "$prefix" >&2
        fi
        printf '%s\n' "$prefix/pfx/drive_c"
        return 0
    fi

    return 1
}

process_profile() {
    local profile="$1"
    local drive_c="$2"
    local name
    name="$(basename "$profile")"

    case "$name" in
        Public|"All Users"|Default|"Default User"|defaultuser0)
            return 0
            ;;
    esac

    redirect_directory "$profile/Documents" "$DOCUMENTS_TARGET" merge
    redirect_directory "$profile/Downloads" "$DOWNLOADS_TARGET" merge

    if [[ ! -e "$profile/My Documents" && ! -L "$profile/My Documents" ]]; then
        ln -s "Documents" "$profile/My Documents"
        printf 'Создан алиас: %s/My Documents -> Documents\n' "$profile"
    fi

    local vortex_data="$profile/AppData/Roaming/Vortex"
    [[ -d "$vortex_data" ]] || return 0

    redirect_directory "$vortex_data/downloads" "$DOWNLOADS_TARGET" merge

    local mods_dir game_dir game_slug target
    while IFS= read -r -d '' mods_dir; do
        game_dir="$(dirname "$mods_dir")"
        game_slug="$(basename "$game_dir")"
        target="$drive_c/Vortex Mods/$game_slug"
        redirect_directory "$mods_dir" "$target" merge
    done < <(
        find "$vortex_data" -mindepth 2 -maxdepth 2 \
            \( -type d -o -type l \) -name mods -print0 2>/dev/null
    )
}

process_prefix() {
    local prefix="$1"
    [[ -d "$prefix" ]] || return 0

    local drive_c
    drive_c="$(prefix_drive_c "$prefix" 2>/dev/null || true)"
    [[ -n "$drive_c" && -d "$drive_c/users" ]] || return 0

    printf '\n=== Префикс: %s ===\n' "$prefix"
    mkdir -p "$drive_c/Vortex Mods"

    local profile
    while IFS= read -r -d '' profile; do
        process_profile "$profile" "$drive_c"
    done < <(
        find "$drive_c/users" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null
    )
}

add_root() {
    local candidate="${1:-}"
    [[ -n "$candidate" ]] || return 0
    candidate="${candidate/#\~/$HOME}"
    [[ -d "$candidate" ]] || return 0

    local old
    for old in "${ROOTS[@]:-}"; do
        [[ "$old" == "$candidate" ]] && return 0
    done
    ROOTS+=("$candidate")
}

collect_lutris_prefixes() {
    local config_dir="$HOME/.local/share/lutris/games"
    [[ -d "$config_dir" ]] || return 0

    local file value
    shopt -s nullglob
    for file in "$config_dir"/*.yml "$config_dir"/*.yaml; do
        while IFS= read -r value; do
            value="${value#*:}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"
            value="${value//\$HOME/$HOME}"
            value="${value/#\~/$HOME}"
            add_root "$value"
        done < <(grep -E '^[[:space:]]+prefix:[[:space:]]*' "$file" 2>/dev/null || true)
    done
    shopt -u nullglob
}

scan_all() {
    ROOTS=()

    add_root "$HOME/.wine"
    add_root "$HOME/Games"
    add_root "$HOME/.local/share/lutris"
    add_root "$HOME/.local/share/bottles/bottles"
    add_root "$HOME/.local/share/Steam/steamapps/compatdata"
    add_root "$HOME/.steam/steam/steamapps/compatdata"
    add_root "$HOME/.var/app/net.lutris.Lutris/data/lutris"
    add_root "$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles"
    add_root "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/compatdata"
    add_root "$HOME/Games/Heroic/Prefixes"
    add_root "/mnt/DataStore/Games"
    add_root "/mnt/DataStore/games"

    if [[ -f "$CONFIG_PATH" ]]; then
        local line
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%%#*}"
            line="${line%"${line##*[![:space:]]}"}"
            line="${line#"${line%%[![:space:]]*}"}"
            [[ -n "$line" ]] && add_root "$line"
        done <"$CONFIG_PATH"
    fi

    collect_lutris_prefixes

    local -A seen=()
    local root drive_c prefix canonical

    for root in "${ROOTS[@]:-}"; do
        [[ -d "$root" ]] || continue

        if [[ -d "$root/drive_c/users" || -d "$root/pfx/drive_c/users" ]]; then
            canonical="$(realpath -m "$root")"
            seen["$canonical"]=1
            process_prefix "$root"
        fi

        while IFS= read -r -d '' drive_c; do
            case "$drive_c" in
                */pfx/drive_c)
                    prefix="${drive_c%/pfx/drive_c}"
                    ;;
                */drive_c)
                    prefix="${drive_c%/drive_c}"
                    ;;
                *)
                    continue
                    ;;
            esac

            canonical="$(realpath -m "$prefix")"
            [[ -n "${seen[$canonical]:-}" ]] && continue
            seen["$canonical"]=1
            process_prefix "$prefix"
        done < <(
            find "$root" -xdev -maxdepth 12 -type d \
                \( -path '*/drive_c' -o -path '*/pfx/drive_c' \) \
                -print0 2>/dev/null
        )
    done

    printf '\nОбработано префиксов: %d\n' "${#seen[@]}"
}

install_global() {
    mkdir -p "$(dirname "$GLOBAL_BIN")" "$SYSTEMD_DIR" "$CONFIG_DIR"
    install -m 0755 "$SELF" "$GLOBAL_BIN"

    if [[ ! -f "$CONFIG_PATH" ]]; then
        cat >"$CONFIG_PATH" <<EOF
# Дополнительные корневые каталоги Wine/Proton-префиксов.
# По одному пути на строку.
#
# /mnt/DataStore/Games
# $HOME/ДругиеПрефиксы
EOF
    fi

    cat >"$SERVICE_PATH" <<EOF
[Unit]
Description=Integrate Linux folders with Wine, Proton and Vortex prefixes
After=default.target

[Service]
Type=oneshot
ExecStart=$GLOBAL_BIN
Nice=10
IOSchedulingClass=idle
EOF

    cat >"$TIMER_PATH" <<'EOF'
[Unit]
Description=Keep Wine, Proton and Vortex prefix integration current

[Timer]
OnBootSec=30s
OnUnitActiveSec=2min
RandomizedDelaySec=15s
Persistent=true
Unit=wine-prefix-integration.service

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now "$APP_NAME.timer"
    echo "Установлена глобальная интеграция: $GLOBAL_BIN"
}

uninstall_global() {
    systemctl --user disable --now "$APP_NAME.timer" 2>/dev/null || true
    systemctl --user stop "$APP_NAME.service" 2>/dev/null || true
    rm -f "$SERVICE_PATH" "$TIMER_PATH" "$GLOBAL_BIN"
    systemctl --user daemon-reload
    echo "Служба и таймер удалены. Созданные ссылки оставлены."
}

if ((UNINSTALL)); then
    uninstall_global
    exit 0
fi

if ((INSTALL_GLOBAL)); then
    install_global
fi

echo "Documents: $DOCUMENTS_TARGET"
echo "Downloads: $DOWNLOADS_TARGET"

if [[ -n "$ONLY_PREFIX" ]]; then
    process_prefix "$(realpath -m "$ONLY_PREFIX")"
else
    scan_all
fi
