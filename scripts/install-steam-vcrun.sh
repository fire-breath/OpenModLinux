#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

APPID="${APPID:-${1:-489830}}"
STEAM_ROOT="${STEAM_ROOT:-$HOME/.local/share/Steam}"
GAME="${GAME:-$STEAM_ROOT/steamapps/common/Skyrim Special Edition}"
COMPAT="${COMPAT:-$STEAM_ROOT/steamapps/compatdata/$APPID}"
PREFIX="$COMPAT/pfx"
SYSTEM32="$PREFIX/drive_c/windows/system32"
PROTON="${PROTON:-$STEAM_ROOT/steamapps/common/Proton - Experimental/proton}"

TS="$(date +%Y%m%d_%H%M%S)"
WORK="$HOME/.cache/openmodlinux-vcrun-direct"
INSTALLER="$WORK/vc_redist.x64.exe"
LOG="$HOME/openmodlinux_vcrun_direct_${TS}.log"
BACKUP="$HOME/openmodlinux_vcrun_direct_backup_${TS}"

exec > >(tee -a "$LOG") 2>&1

pause() {
    echo
    echo "Лог: $LOG"
    echo "Резервная копия: $BACKUP"
    if [[ -t 0 ]]; then
        read -r -p "Нажмите Enter, чтобы закрыть окно..." _
    fi
}

finish() {
    local rc=$?
    trap - EXIT
    echo
    echo "============================================================"
    if (( rc == 0 )); then
        echo "Microsoft Visual C++ Runtime установлен и проверен."
    else
        echo "Операция завершилась с ошибкой. Код: $rc"
    fi
    echo "============================================================"
    pause
    exit "$rc"
}
trap finish EXIT

fail() {
    echo "ОШИБКА: $*" >&2
    exit 1
}

(( EUID != 0 )) || fail "Не запускайте этот скрипт через sudo."
command -v curl >/dev/null 2>&1 || fail "Не найдена команда curl."
command -v file >/dev/null 2>&1 || fail "Не найдена команда file."

[[ -x "$PROTON" ]] || fail "Proton Experimental не найден: $PROTON"
[[ -d "$SYSTEM32" ]] || fail "Префикс Skyrim не найден: $PREFIX"
[[ -f "$GAME/SkyrimSE.exe" ]] || fail "SkyrimSE.exe не найден: $GAME"

if pgrep -af 'SkyrimSE\.exe|skse64_loader\.exe' >/dev/null 2>&1; then
    echo "Найдены процессы Skyrim:"
    pgrep -af 'SkyrimSE\.exe|skse64_loader\.exe' || true
    fail "Полностью закройте Skyrim перед продолжением."
fi

mkdir -p "$WORK" "$BACKUP"

echo "=== Пути ==="
echo "Proton: $PROTON"
echo "Префикс: $PREFIX"
echo "Игра: $GAME"
echo "Установщик: $INSTALLER"

echo
echo "=== Резервная копия ==="
for f in user.reg system.reg userdef.reg; do
    if [[ -f "$PREFIX/$f" ]]; then
        cp -a "$PREFIX/$f" "$BACKUP/$f"
        echo "Сохранено: $PREFIX/$f"
    fi
done

RUNTIME_DLLS=(
    msvcp140.dll
    msvcp140_1.dll
    msvcp140_2.dll
    msvcp140_atomic_wait.dll
    msvcp140_codecvt_ids.dll
    vcruntime140.dll
    vcruntime140_1.dll
    concrt140.dll
)

for dll in "${RUNTIME_DLLS[@]}"; do
    if [[ -e "$SYSTEM32/$dll" ]]; then
        cp -aL "$SYSTEM32/$dll" "$BACKUP/$dll"
    fi
done

echo "Резервная копия: $BACKUP"

echo
echo "=== Получение официального установщика Microsoft ==="
URL="https://aka.ms/vc14/vc_redist.x64.exe"

NEED_DOWNLOAD=1
if [[ -f "$INSTALLER" ]]; then
    SIZE="$(stat -c '%s' "$INSTALLER" 2>/dev/null || echo 0)"
    if (( SIZE > 10000000 )); then
        NEED_DOWNLOAD=0
        echo "Используется уже скачанный файл: $INSTALLER"
    fi
fi

if (( NEED_DOWNLOAD )); then
    curl -fL \
        --retry 3 \
        --retry-delay 2 \
        --connect-timeout 30 \
        -o "$INSTALLER.tmp" \
        "$URL"

    mv -f "$INSTALLER.tmp" "$INSTALLER"
fi

chmod 0644 "$INSTALLER"

echo
echo "Тип файла:"
file "$INSTALLER"
echo "Размер: $(stat -c '%s' "$INSTALLER") байт"
sha256sum "$INSTALLER"

# vc_redist.x64.exe является самораспаковывающимся bootstrapper.
# Его внешний EXE-загрузчик может определяться как PE32/i386,
# хотя внутри устанавливается именно пакет x64.
if ! file "$INSTALLER" | grep -qi 'PE32.*executable.*MS Windows'; then
    fail "Скачанный файл не распознан как Windows PE executable."
fi

SIZE="$(stat -c '%s' "$INSTALLER")"
(( SIZE > 10000000 )) || fail "Установщик подозрительно мал: $SIZE байт."

export STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT"
export STEAM_COMPAT_DATA_PATH="$COMPAT"
export STEAM_COMPAT_INSTALL_PATH="$GAME"
export SteamAppId="$APPID"
export SteamGameId="$APPID"

echo
echo "=== Состояние runtime до установки ==="
for dll in msvcp140.dll vcruntime140.dll vcruntime140_1.dll; do
    if [[ -f "$SYSTEM32/$dll" ]]; then
        file "$SYSTEM32/$dll" || true
        stat -c 'Размер=%s  Изменён=%y  %n' "$SYSTEM32/$dll"
        sha256sum "$SYSTEM32/$dll"
    else
        echo "ОТСУТСТВУЕТ: $SYSTEM32/$dll"
    fi
done

echo
echo "=== Установка Microsoft Visual C++ 2015-2022 x64 ==="
echo "Команда: vc_redist.x64.exe /install /quiet /norestart"

set +e
"$PROTON" run "$INSTALLER" /install /quiet /norestart
INSTALL_RC=$?
set -e

# Код Windows 3010 (установка успешна, требуется перезагрузка)
# в Unix может отображаться как 194.
if (( INSTALL_RC != 0 && INSTALL_RC != 194 )); then
    echo "Код установщика: $INSTALL_RC"
    fail "Установщик Microsoft Visual C++ завершился с ошибкой."
fi

echo "Код установщика: $INSTALL_RC"

echo
echo "=== Установка DLL overrides ==="
for dll in \
    msvcp140 \
    msvcp140_1 \
    msvcp140_2 \
    msvcp140_atomic_wait \
    msvcp140_codecvt_ids \
    vcruntime140 \
    vcruntime140_1
do
    "$PROTON" run reg.exe add \
        'HKCU\Software\Wine\DllOverrides' \
        /v "$dll" \
        /d native,builtin \
        /f
done

echo
echo "=== Проверка реестра Microsoft VC Runtime ==="
"$PROTON" run reg.exe query \
    'HKLM\Software\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' || true

echo
echo "=== Состояние runtime после установки ==="
REQUIRED=(
    msvcp140.dll
    vcruntime140.dll
    vcruntime140_1.dll
)

MISSING=0
BUILTIN=0

for dll in "${REQUIRED[@]}"; do
    path="$SYSTEM32/$dll"
    echo

    if [[ ! -f "$path" ]]; then
        echo "ОТСУТСТВУЕТ: $path"
        MISSING=1
        continue
    fi

    DESC="$(file "$path" 2>/dev/null || true)"
    echo "$DESC"
    stat -c 'Размер=%s  Изменён=%y  %n' "$path"
    sha256sum "$path"

    if grep -qi 'for WINE' <<<"$DESC"; then
        echo "ПРЕДУПРЕЖДЕНИЕ: это всё ещё встроенная DLL Wine."
        BUILTIN=1
    fi
done

echo
echo "=== Overrides в user.reg ==="
grep -nE \
    '"(msvcp140|msvcp140_1|msvcp140_2|msvcp140_atomic_wait|msvcp140_codecvt_ids|vcruntime140|vcruntime140_1)"=' \
    "$PREFIX/user.reg" 2>/dev/null || true

(( MISSING == 0 )) || fail "После установки отсутствуют обязательные DLL."
(( BUILTIN == 0 )) || fail \
    "После установки одна из обязательных DLL всё ещё является встроенной Wine."

echo
echo "=== Steam prefix runtime ready ==="
echo "Для Skyrim SE параметры запуска Steam для проверки:"
echo 'PROTON_LOG=1 WINEDLLOVERRIDES="d3dx9_42=n,b;msvcp140=n,b;vcruntime140=n,b;vcruntime140_1=n,b" bash -c '\''args=("${@/SkyrimSELauncher.exe/skse64_loader.exe}"); args=("${args[@]/SkyrimSE.exe/skse64_loader.exe}"); exec "${args[@]}"'\'' -- %command%'
