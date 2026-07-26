#!/usr/bin/env bash
set -u

GAME="${GAME:-$HOME/.local/share/Steam/steamapps/common/Skyrim Special Edition}"
DOWNLOADS="${DOWNLOADS:-$HOME/Загрузки}"
LOG="$HOME/engine_fixes_preloader_install_$(date +%Y%m%d_%H%M%S).log"

exec > >(tee -a "$LOG") 2>&1

pause() {
    echo
    echo "Лог: $LOG"
    if [[ -t 0 ]]; then
        read -r -p "Нажмите Enter, чтобы закрыть окно..." _
    fi
}

finish() {
    local rc=$?
    trap - EXIT
    echo
    if (( rc == 0 )); then
        echo "Установка завершена успешно."
    else
        echo "Установка завершилась с ошибкой. Код: $rc"
    fi
    pause
    exit "$rc"
}
trap finish EXIT

fail() {
    echo "ОШИБКА: $*" >&2
    exit 1
}

[[ -d "$GAME" ]] || fail "Папка Skyrim не найдена: $GAME"

command -v 7z >/dev/null 2>&1 || fail     "Не найдена команда 7z. Установите пакет: sudo apt install p7zip-full"

ARCHIVE="${1:-}"


if [[ -n "$ARCHIVE" && ! -f "$ARCHIVE" ]]; then
    fail "Архив не найден: $ARCHIVE"
fi

if [[ -z "$ARCHIVE" ]]; then
ARCHIVE="$(
    find "$DOWNLOADS" -maxdepth 4 -type f         \( -iname '*engine*fixes*preloader*.7z'         -o -iname '*engine*fixes*preloader*.zip'         -o -iname '*engine*fixes*preloader*.rar'         -o -iname '*engine*fixes*part*2*.7z'         -o -iname '*engine*fixes*part*2*.zip'         -o -iname '*engine*fixes*part*2*.rar'         -o -iname '*d3dx9_42*.7z'         -o -iname '*d3dx9_42*.zip'         -o -iname '*d3dx9_42*.rar' \)         -printf '%T@ %p\n' 2>/dev/null |
    sort -nr |
    head -1 |
    cut -d' ' -f2-
)"
fi

if [[ -z "$ARCHIVE" ]]; then
    echo "В папке $DOWNLOADS подходящий архив не найден."
    echo
    echo "Последние архивы в папке загрузок:"
    find "$DOWNLOADS" -maxdepth 3 -type f         \( -iname '*.7z' -o -iname '*.zip' -o -iname '*.rar' \)         -printf '%TY-%Tm-%Td %TH:%TM  %p\n' 2>/dev/null |
        sort -r |
        head -20
    fail "Сначала скачайте архив Engine Fixes Preloader."
fi

echo "Найден архив:"
echo "$ARCHIVE"
echo

TMP="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP"
}
trap 'cleanup; finish' EXIT

7z x -y "$ARCHIVE" -o"$TMP" || fail "Не удалось распаковать архив."

DLL="$(find "$TMP" -type f -iname 'd3dx9_42.dll' -print -quit)"

if [[ -z "$DLL" ]]; then
    echo "Содержимое архива:"
    find "$TMP" -maxdepth 4 -type f -printf '%P\n' | head -100
    fail "В архиве отсутствует d3dx9_42.dll."
fi

TARGET="$GAME/d3dx9_42.dll"

if [[ -f "$TARGET" ]]; then
    BACKUP="${TARGET}.backup_$(date +%Y%m%d_%H%M%S)"
    cp -a "$TARGET" "$BACKUP"
    echo "Существующий файл сохранён:"
    echo "$BACKUP"
fi

install -m 0644 "$DLL" "$TARGET"

echo
echo "Установлено:"
ls -lh "$TARGET"

echo
echo "Проверка основных файлов:"
for FILE in SkyrimSE.exe skse64_loader.exe d3dx9_42.dll; do
    if [[ -f "$GAME/$FILE" ]]; then
        echo "Найден: $FILE"
    else
        echo "ОТСУТСТВУЕТ: $FILE"
    fi
done
