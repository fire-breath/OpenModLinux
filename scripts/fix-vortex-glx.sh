#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PROJECT="${OPENMODLINUX_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
LUTRIS_CONFIG_DIR="$HOME/.local/share/lutris/games"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$HOME/vortex_glx_fix_${TS}.log"

exec > >(tee -a "$LOG") 2>&1

finish() {
    rc=$?
    trap - EXIT
    echo
    echo "============================================================"
    if (( rc == 0 )); then
        echo "Исправление графического запуска Vortex завершено успешно."
    else
        echo "Исправление завершилось с ошибкой. Код: $rc"
    fi
    echo "Лог: $LOG"
    echo "============================================================"
    exit "$rc"
}
trap finish EXIT

if (( EUID == 0 )); then
    echo "Не запускайте через sudo." >&2
    exit 1
fi

if pgrep -af '[V]ortex\.exe' >/dev/null 2>&1; then
    echo "Сначала полностью закройте Vortex." >&2
    pgrep -af '[V]ortex\.exe' >&2 || true
    exit 1
fi

command -v python3 >/dev/null 2>&1 || {
    echo "Не найдена команда python3." >&2
    exit 1
}

echo "=== Причина исправления ==="
echo "Убираем принудительный NVIDIA PRIME/GLX для интерфейса Vortex,"
echo "отключаем GameMode и запускаем Electron без аппаратного GPU."
echo

python3 - "$LUTRIS_CONFIG_DIR" "$PROJECT" "$TS" <<'PY'
from __future__ import annotations

from pathlib import Path
import re
import shutil
import sys

config_dir = Path(sys.argv[1])
project = Path(sys.argv[2])
timestamp = sys.argv[3]

electron_args = [
    "--disable-gpu",
    "--disable-gpu-compositing",
    "--disable-gpu-sandbox",
    "--no-sandbox",
]

remove_keys = {
    "DRI_PRIME",
    "VK_DRIVER_FILES",
    "VK_ICD_FILENAMES",
    "__GLX_VENDOR_LIBRARY_NAME",
    "__VK_LAYER_NV_optimus",
    "__NV_PRIME_RENDER_OFFLOAD",
    "DXVK_FILTER_DEVICE_UUID",
}

def is_vortex_config(path: Path, text: str) -> bool:
    low = text.lower()
    return (
        "vortex-mod-manager" in low
        or "vortex mod manager" in low
        or "/games/vortex-mod-manager" in low
        or "program files/vortex/vortex.exe" in low
    )

def merge_args(value: str) -> str:
    raw = value.strip().strip('"').strip("'")
    parts = raw.split() if raw else []
    for arg in electron_args:
        if arg not in parts:
            parts.append(arg)
    return " ".join(parts)

def patch_local_config(path: Path) -> bool:
    text = path.read_text(encoding="utf-8", errors="replace")
    if not is_vortex_config(path, text):
        return False

    lines = text.splitlines()
    out: list[str] = []
    in_game = False
    game_indent = 0
    args_done = False
    gamemode_done = False

    for line in lines:
        stripped = line.lstrip()
        indent = len(line) - len(stripped)

        # Удаляем только конкретные переменные принудительного GPU.
        key_match = re.match(r"^([A-Za-z0-9_]+)\s*:", stripped)
        if key_match and key_match.group(1) in remove_keys:
            continue

        # Также убираем строковые записи формата KEY=VALUE.
        if any(re.search(rf"(^|[\s\"']){re.escape(key)}=", stripped) for key in remove_keys):
            continue

        if re.match(r"^game:\s*$", stripped) and indent == 0:
            in_game = True
            game_indent = indent
            out.append(line)
            continue

        if in_game and stripped and indent <= game_indent:
            if not args_done:
                out.append("  args: " + " ".join(electron_args))
                args_done = True
            in_game = False

        if in_game and re.match(r"^args:\s*", stripped):
            prefix = line[:indent]
            value = stripped.split(":", 1)[1]
            out.append(f"{prefix}args: {merge_args(value)}")
            args_done = True
            continue

        if re.match(r"^gamemode:\s*", stripped):
            prefix = line[:indent]
            out.append(f"{prefix}gamemode: false")
            gamemode_done = True
            continue

        if re.match(r"^(prime|optimus):\s*true\s*$", stripped, re.IGNORECASE):
            key = stripped.split(":", 1)[0]
            prefix = line[:indent]
            out.append(f"{prefix}{key}: false")
            continue

        out.append(line)

    if in_game and not args_done:
        out.append("  args: " + " ".join(electron_args))
        args_done = True

    if not args_done:
        # Нестандартный конфиг: создаём/добавляем корневой game.
        insert_at = 0
        for i, line in enumerate(out):
            if re.match(r"^game:\s*$", line):
                insert_at = i + 1
                break
        if insert_at:
            out.insert(insert_at, "  args: " + " ".join(electron_args))
        else:
            out[0:0] = ["game:", "  args: " + " ".join(electron_args)]

    if not gamemode_done:
        system_index = None
        for i, line in enumerate(out):
            if re.match(r"^system:\s*$", line):
                system_index = i
                break
        if system_index is not None:
            out.insert(system_index + 1, "  gamemode: false")
        else:
            out.extend(["system:", "  gamemode: false"])

    updated = "\n".join(out) + "\n"
    if updated == text:
        return False

    backup = path.with_name(path.name + f".backup_glx_{timestamp}")
    shutil.copy2(path, backup)
    path.write_text(updated, encoding="utf-8")
    print(f"Исправлен локальный конфиг: {path}")
    print(f"Резервная копия: {backup}")
    return True

def patch_project_yaml(path: Path) -> bool:
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    out: list[str] = []
    in_script_game = False
    game_indent = None
    args_done = False
    in_script_system = False
    system_indent = None
    gamemode_done = False

    for line in lines:
        stripped = line.lstrip()
        indent = len(line) - len(stripped)

        key_match = re.match(r"^([A-Za-z0-9_]+)\s*:", stripped)
        if key_match and key_match.group(1) in remove_keys:
            continue

        if re.match(r"^game:\s*$", stripped) and indent == 2:
            in_script_game = True
            game_indent = indent
            out.append(line)
            continue

        if in_script_game and stripped and indent <= int(game_indent):
            if not args_done:
                out.append("    args: " + " ".join(electron_args))
                args_done = True
            in_script_game = False

        if in_script_game and re.match(r"^args:\s*", stripped):
            prefix = line[:indent]
            value = stripped.split(":", 1)[1]
            out.append(f"{prefix}args: {merge_args(value)}")
            args_done = True
            continue

        if re.match(r"^system:\s*$", stripped) and indent == 2:
            in_script_system = True
            system_indent = indent
            out.append(line)
            continue

        if in_script_system and stripped and indent <= int(system_indent):
            if not gamemode_done:
                out.append("    gamemode: false")
                gamemode_done = True
            in_script_system = False

        if in_script_system and re.match(r"^gamemode:\s*", stripped):
            out.append("    gamemode: false")
            gamemode_done = True
            continue

        out.append(line)

    if in_script_game and not args_done:
        out.append("    args: " + " ".join(electron_args))
        args_done = True

    if in_script_system and not gamemode_done:
        out.append("    gamemode: false")
        gamemode_done = True

    if not args_done:
        raise SystemExit(f"Не найден раздел script.game в {path}")

    if not gamemode_done:
        # Добавляем system перед installer внутри script.
        installer_index = None
        for i, line in enumerate(out):
            if re.match(r"^\s{2}installer:\s*$", line):
                installer_index = i
                break
        block = ["  system:", "    gamemode: false", ""]
        if installer_index is None:
            out.extend(block)
        else:
            out[installer_index:installer_index] = block

    updated = "\n".join(out) + "\n"
    if updated == text:
        return False

    backup = path.with_name(path.name + f".backup_glx_{timestamp}")
    shutil.copy2(path, backup)
    path.write_text(updated, encoding="utf-8")
    print(f"Исправлен шаблон проекта: {path}")
    print(f"Резервная копия: {backup}")
    return True

changed = 0

if config_dir.is_dir():
    for path in sorted(list(config_dir.glob("*.yml")) + list(config_dir.glob("*.yaml"))):
        changed += int(patch_local_config(path))
else:
    print(f"Каталог Lutris не найден: {config_dir}")

project_yaml = project / "lutris" / "vortex.yml"
if project_yaml.is_file():
    changed += int(patch_project_yaml(project_yaml))
else:
    print(f"Шаблон проекта не найден: {project_yaml}")

print(f"Изменено файлов: {changed}")
PY

echo
echo "=== Проверка YAML и фиксация проекта ==="

if [[ -f "$PROJECT/scripts/validate-yaml.py" ]]; then
    (
        cd "$PROJECT"
        python3 scripts/validate-yaml.py
    )
fi


echo
echo "Полностью закройте Lutris и запустите его снова."
echo "Vortex будет запускаться без NVIDIA PRIME и без аппаратного GPU Electron."
