#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

APP_NAME="wine-prefix-integration"
CONFIG_PATH="$HOME/.config/$APP_NAME/roots.conf"
ONLY_PREFIX=""

while (($#)); do
    case "$1" in
        --prefix)
            [[ $# -ge 2 ]] || {
                echo "--prefix требует путь" >&2
                exit 2
            }
            ONLY_PREFIX="$2"
            shift 2
            ;;
        -h|--help)
            echo "Использование: $0 [--prefix ПРЕФИКС]"
            exit 0
            ;;
        *)
            echo "Неизвестный параметр: $1" >&2
            exit 2
            ;;
    esac
done

resolve_xdg_dir() {
    local kind="$1"
    local ru_name="$2"
    local en_name="$3"
    local result=""

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

DOCUMENTS_TARGET="${WINE_DOCUMENTS_TARGET:-$(resolve_xdg_dir DOCUMENTS Документы Documents)}"
DOWNLOADS_TARGET="${WINE_DOWNLOADS_TARGET:-$(resolve_xdg_dir DOWNLOAD Загрузки Downloads)}"

backup_name() {
    local path="$1"
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    local result="${path}.before-global-fix_${ts}"
    local index=1

    while [[ -e "$result" || -L "$result" ]]; do
        result="${path}.before-global-fix_${ts}_${index}"
        ((index++))
    done

    printf '%s\n' "$result"
}

is_empty_dir() {
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

    cp -an --reflink=auto "$source"/. "$target"/
}

redirect_shared_directory() {
    local source="$1"
    local target="$2"

    mkdir -p "$(dirname "$source")" "$target"

    if [[ -L "$source" ]]; then
        local resolved
        resolved="$(readlink -f "$source" 2>/dev/null || true)"
        if [[ "$resolved" == "$(realpath -m "$target")" ]]; then
            echo "OK: $source -> $target"
            return 0
        fi
        rm -f -- "$source"
    elif [[ -d "$source" ]]; then
        if is_empty_dir "$source"; then
            rmdir -- "$source"
        else
            merge_without_overwrite "$source" "$target"
            local backup
            backup="$(backup_name "$source")"
            mv -- "$source" "$backup"
            echo "Сохранён прежний каталог: $backup"
        fi
    elif [[ -e "$source" ]]; then
        local backup
        backup="$(backup_name "$source")"
        mv -- "$source" "$backup"
        echo "Сохранён прежний объект: $backup"
    fi

    ln -s -- "$target" "$source"
    echo "Создано: $source -> $target"
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
            echo "Создано: $prefix/drive_c -> pfx/drive_c" >&2
        fi
        printf '%s\n' "$prefix/pfx/drive_c"
        return 0
    fi

    return 1
}

materialize_staging_link() {
    local link="$1"
    local drive_c="$2"

    [[ -L "$link" ]] || return 0

    local target
    target="$(readlink -f "$link" 2>/dev/null || true)"

    echo
    echo "Исправляется staging-ссылка:"
    echo "  $link"
    echo "  -> ${target:-<не существует>}"

    rm -f -- "$link"
    mkdir -p "$(dirname "$link")"

    if [[ -n "$target" && -d "$target" ]]; then
        local parent_device target_device
        parent_device="$(stat -c '%d' "$(dirname "$link")")"
        target_device="$(stat -c '%d' "$target")"

        case "$target" in
            "$drive_c/Vortex Mods/"*)
                if [[ "$parent_device" == "$target_device" ]] && mv -- "$target" "$link"; then
                    echo "Каталог перенесён в реальный staging: $link"
                    rmdir --ignore-fail-on-non-empty "$drive_c/Vortex Mods" 2>/dev/null || true
                    return 0
                fi
                ;;
        esac

        mkdir -p "$link"
        merge_without_overwrite "$target" "$link"

        local old_backup
        old_backup="$(backup_name "$target")"
        if mv -- "$target" "$old_backup" 2>/dev/null; then
            echo "Старая цель сохранена: $old_backup"
        else
            echo "Старая цель оставлена без изменения: $target"
        fi
    else
        mkdir -p "$link"
    fi

    [[ -d "$link" && ! -L "$link" ]] || {
        echo "Не удалось создать реальный staging-каталог: $link" >&2
        return 1
    }

    echo "Создан реальный staging-каталог: $link"
}

repair_vortex_staging() {
    local profile="$1"
    local drive_c="$2"
    local vortex_root="$profile/AppData/Roaming/Vortex"

    [[ -d "$vortex_root" ]] || return 0

    # Download можно связывать с Linux «Загрузки».
    redirect_shared_directory "$vortex_root/downloads" "$DOWNLOADS_TARGET"

    # Staging должен быть настоящим каталогом, не symlink.
    local staging
    while IFS= read -r -d '' staging; do
        materialize_staging_link "$staging" "$drive_c"
    done < <(
        find "$vortex_root" -mindepth 2 -maxdepth 2 -type l \
            -name mods -print0 2>/dev/null
    )
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

    redirect_shared_directory "$profile/Documents" "$DOCUMENTS_TARGET"
    redirect_shared_directory "$profile/Downloads" "$DOWNLOADS_TARGET"

    if [[ ! -e "$profile/My Documents" && ! -L "$profile/My Documents" ]]; then
        ln -s "Documents" "$profile/My Documents"
        echo "Создан алиас: $profile/My Documents -> Documents"
    fi

    repair_vortex_staging "$profile" "$drive_c"
}

process_prefix() {
    local prefix="$1"
    [[ -d "$prefix" ]] || return 0

    local drive_c
    drive_c="$(prefix_drive_c "$prefix" 2>/dev/null || true)"
    [[ -n "$drive_c" && -d "$drive_c/users" ]] || return 0

    echo
    echo "=== Префикс: $prefix ==="

    local profile
    while IFS= read -r -d '' profile; do
        process_profile "$profile" "$drive_c"
    done < <(
        find "$drive_c/users" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null
    )
}

ROOTS=()

add_root() {
    local value="${1:-}"
    [[ -n "$value" ]] || return 0
    value="${value/#\~/$HOME}"
    [[ -d "$value" ]] || return 0

    local old
    for old in "${ROOTS[@]:-}"; do
        [[ "$old" == "$value" ]] && return 0
    done

    ROOTS+=("$value")
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
                */pfx/drive_c) prefix="${drive_c%/pfx/drive_c}" ;;
                */drive_c)     prefix="${drive_c%/drive_c}" ;;
                *) continue ;;
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

    echo
    echo "Обработано префиксов: ${#seen[@]}"
}

echo "Documents: $DOCUMENTS_TARGET"
echo "Downloads: $DOWNLOADS_TARGET"

if [[ -n "$ONLY_PREFIX" ]]; then
    process_prefix "$(realpath -m "$ONLY_PREFIX")"
else
    scan_all
fi
