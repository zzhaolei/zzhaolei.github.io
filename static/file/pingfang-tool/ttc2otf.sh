#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
用法：
  ./ttc2otf.sh
  ./ttc2otf.sh /path/to/PingFang.ttc
  ./ttc2otf.sh /path/to/PingFang.ttc /path/to/output

参数：
  第一个参数：可选，指定 PingFang.ttc 路径
  第二个参数：可选，指定输出目录，默认 ./PingFang-Split

示例：
  ./ttc2otf.sh
  ./ttc2otf.sh "/System/Library/Fonts/PingFang.ttc"
  ./ttc2otf.sh ./PingFang.ttc ./output
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

INPUT="${1:-}"
OUTPUT="${2:-$PWD/PingFang-Split}"

# 自动查找 PingFang.ttc
if [[ -z "$INPUT" ]]; then
    echo "正在搜索 PingFang.ttc……"

    SEARCH_DIRS=(
        "/System/Library/Fonts"
        "/System/Library/AssetsV2"
        "/Library/Fonts"
        "$HOME/Library/Fonts"
    )

    FOUND=()

    for dir in "${SEARCH_DIRS[@]}"; do
        [[ -d "$dir" ]] || continue

        while IFS= read -r -d '' file; do
            FOUND+=("$file")
        done < <(
            find "$dir" \
                -type f \
                \( -iname 'PingFang.ttc' -o -iname '*PingFang*.ttc' \) \
                -print0 2>/dev/null
        )
    done

    if [[ ${#FOUND[@]} -eq 0 ]]; then
        echo "错误：没有找到 PingFang.ttc。" >&2
        echo "请先在“字体册”中下载或启用苹方，或者手动传入文件路径。" >&2
        exit 1
    fi

    if [[ ${#FOUND[@]} -eq 1 ]]; then
        INPUT="${FOUND[0]}"
    else
        echo
        echo "发现多个候选文件："

        for i in "${!FOUND[@]}"; do
            printf '  [%d] %s\n' "$((i + 1))" "${FOUND[$i]}"
        done

        echo
        read -r -p "请选择文件编号 [1]: " choice
        choice="${choice:-1}"

        if ! [[ "$choice" =~ ^[0-9]+$ ]] ||
            ((choice < 1 || choice > ${#FOUND[@]})); then
            echo "错误：无效编号。" >&2
            exit 1
        fi

        INPUT="${FOUND[$((choice - 1))]}"
    fi
fi

if [[ ! -f "$INPUT" ]]; then
    echo "错误：文件不存在：$INPUT" >&2
    exit 1
fi

# 优先使用当前环境中的 Python 3
if ! command -v python3 >/dev/null 2>&1; then
    echo "错误：没有找到 python3。" >&2
    exit 1
fi

# 检查 FontTools
if ! python3 -c 'import fontTools' >/dev/null 2>&1; then
    echo "未安装 FontTools。"
    echo
    echo "可以执行以下任意一条命令安装："
    echo "  python3 -m pip install --user fonttools"
    echo "  uv pip install fonttools"
    echo
    exit 1
fi

mkdir -p "$OUTPUT"

echo
echo "输入文件：$INPUT"
echo "输出目录：$OUTPUT"
echo

python3 - "$INPUT" "$OUTPUT" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

from fontTools.ttLib import TTCollection, TTFont


input_path = Path(sys.argv[1]).expanduser().resolve()
output_root = Path(sys.argv[2]).expanduser().resolve()

# OpenType name table 中常用的名称 ID
NAME_COPYRIGHT = 0
NAME_FAMILY = 1
NAME_SUBFAMILY = 2
NAME_FULL = 4
NAME_POSTSCRIPT = 6
NAME_TYPO_FAMILY = 16
NAME_TYPO_SUBFAMILY = 17


def decode_name(record) -> str | None:
    """尽可能可靠地解码 name 表记录。"""
    try:
        value = record.toUnicode()
    except Exception:
        try:
            value = record.string.decode("utf-16-be")
        except Exception:
            try:
                value = record.string.decode("utf-8")
            except Exception:
                return None

    value = value.strip()
    return value or None


def get_name(font: TTFont, name_id: int) -> str | None:
    """优先获取英文名称，找不到时返回任意可解码名称。"""
    name_table = font.get("name")

    if name_table is None:
        return None

    candidates: list[tuple[int, str]] = []

    for record in name_table.names:
        if record.nameID != name_id:
            continue

        value = decode_name(record)
        if not value:
            continue

        # Windows 英文和 Macintosh 英文优先
        priority = 10

        if record.platformID == 3 and record.langID in (0x0409, 0):
            priority = 0
        elif record.platformID == 1 and record.langID == 0:
            priority = 1
        elif record.platformID == 0:
            priority = 2

        candidates.append((priority, value))

    if not candidates:
        return None

    candidates.sort(key=lambda item: item[0])
    return candidates[0][1]


def sanitize_filename(value: str) -> str:
    """将字体名称转换为适合作为文件名的形式。"""
    value = value.strip()

    replacements = {
        "苹方-简": "PingFang-SC",
        "蘋方-繁": "PingFang-TC",
        "蘋方-港": "PingFang-HK",
        "苹方": "PingFang",
        "蘋方": "PingFang",
    }

    for source, target in replacements.items():
        value = value.replace(source, target)

    value = re.sub(r"\s+", "-", value)
    value = value.replace("/", "-")
    value = value.replace("\\", "-")
    value = value.replace(":", "-")
    value = re.sub(r'[<>:"|?*\x00-\x1f]', "", value)
    value = re.sub(r"-+", "-", value)

    return value.strip("-. ") or "Unnamed-Font"


def detect_region(*names: str | None) -> str:
    combined = " ".join(name for name in names if name).lower()

    if (
        "pingfang sc" in combined
        or "pingfang-sc" in combined
        or "苹方-简" in combined
        or "简体" in combined
    ):
        return "SC"

    if (
        "pingfang tc" in combined
        or "pingfang-tc" in combined
        or "蘋方-繁" in combined
        or "繁體" in combined
    ):
        return "TC"

    if (
        "pingfang hk" in combined
        or "pingfang-hk" in combined
        or "蘋方-港" in combined
        or "香港" in combined
    ):
        return "HK"

    return "Other"


def normalize_weight(value: str | None) -> str:
    if not value:
        return "Regular"

    lowered = value.lower().replace(" ", "").replace("-", "")

    mapping = (
        ("ultralight", "Ultralight"),
        ("extralight", "Ultralight"),
        ("thin", "Thin"),
        ("light", "Light"),
        ("regular", "Regular"),
        ("normal", "Regular"),
        ("medium", "Medium"),
        ("semibold", "Semibold"),
        ("demibold", "Semibold"),
        ("bold", "Bold"),
    )

    for token, normalized in mapping:
        if token in lowered:
            return normalized

    return sanitize_filename(value)


def output_extension(font: TTFont) -> str:
    # OTTO 通常表示 CFF/CFF2 轮廓，应该保存为 OTF。
    if font.sfntVersion == "OTTO":
        return ".otf"

    return ".ttf"


def unique_path(path: Path) -> Path:
    if not path.exists():
        return path

    counter = 2

    while True:
        candidate = path.with_name(
            f"{path.stem}-{counter}{path.suffix}"
        )

        if not candidate.exists():
            return candidate

        counter += 1


def split_collection(path: Path) -> int:
    collection = TTCollection(str(path), lazy=False)
    count = 0

    try:
        total = len(collection.fonts)
        print(f"字体集合中包含 {total} 个字体成员。\n")

        for index, font in enumerate(collection.fonts):
            family = (
                get_name(font, NAME_TYPO_FAMILY)
                or get_name(font, NAME_FAMILY)
            )

            subfamily = (
                get_name(font, NAME_TYPO_SUBFAMILY)
                or get_name(font, NAME_SUBFAMILY)
            )

            full_name = get_name(font, NAME_FULL)
            postscript_name = get_name(font, NAME_POSTSCRIPT)

            region = detect_region(
                family,
                subfamily,
                full_name,
                postscript_name,
            )

            weight = normalize_weight(subfamily)

            if region == "Other":
                base_name = (
                    postscript_name
                    or full_name
                    or f"PingFang-{index:02d}"
                )
                filename = sanitize_filename(base_name)
            else:
                filename = f"PingFang-{region}-{weight}"

            extension = output_extension(font)

            region_dir = output_root / region
            region_dir.mkdir(parents=True, exist_ok=True)

            output_path = unique_path(region_dir / f"{filename}{extension}")

            # 重新计算校验和，避免保留旧的 checksumAdjustment。
            font.recalcTimestamp = False
            font.recalcBBoxes = True

            font.save(str(output_path), reorderTables=True)
            count += 1

            relative = output_path.relative_to(output_root)

            print(f"[{index + 1:02d}/{total:02d}] {relative}")
            print(f"       family:     {family or '-'}")
            print(f"       subfamily:  {subfamily or '-'}")
            print(f"       full name:  {full_name or '-'}")
            print(f"       PostScript: {postscript_name or '-'}")
            print()

    finally:
        collection.close()

    return count


def extract_single_font(path: Path) -> int:
    """兼容用户传入单个 TTF/OTF 的情况。"""
    font = TTFont(str(path), lazy=False)

    try:
        family = (
            get_name(font, NAME_TYPO_FAMILY)
            or get_name(font, NAME_FAMILY)
        )
        subfamily = (
            get_name(font, NAME_TYPO_SUBFAMILY)
            or get_name(font, NAME_SUBFAMILY)
        )
        full_name = get_name(font, NAME_FULL)
        postscript_name = get_name(font, NAME_POSTSCRIPT)

        region = detect_region(
            family,
            subfamily,
            full_name,
            postscript_name,
        )
        weight = normalize_weight(subfamily)

        if region == "Other":
            filename = sanitize_filename(
                postscript_name or full_name or path.stem
            )
        else:
            filename = f"PingFang-{region}-{weight}"

        region_dir = output_root / region
        region_dir.mkdir(parents=True, exist_ok=True)

        extension = output_extension(font)
        output_path = unique_path(region_dir / f"{filename}{extension}")

        font.save(str(output_path), reorderTables=True)
        print(output_path.relative_to(output_root))

    finally:
        font.close()

    return 1


output_root.mkdir(parents=True, exist_ok=True)

try:
    extracted = split_collection(input_path)
except Exception as collection_error:
    try:
        extracted = extract_single_font(input_path)
    except Exception:
        print(
            f"无法读取字体文件：{input_path}\n"
            f"TTC 读取错误：{collection_error}",
            file=sys.stderr,
        )
        raise

print(f"\n完成，共导出 {extracted} 个字体文件。")
print(f"输出目录：{output_root}")
PY

echo
echo "字体文件列表："
find "$OUTPUT" -type f \( -iname '*.ttf' -o -iname '*.otf' \) \
    -print | sort
