#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTCollection, TTFont, newTable


def get_name(font: TTFont, name_id: int) -> str | None:
    """优先读取英文名称，找不到时返回任意可解码名称。"""
    name_table = font.get("name")
    if name_table is None:
        return None

    candidates: list[tuple[int, str]] = []

    for record in name_table.names:
        if record.nameID != name_id:
            continue

        try:
            value = record.toUnicode().strip()
        except Exception:
            continue

        if not value:
            continue

        priority = 10

        # Windows 英文
        if record.platformID == 3 and record.langID in (0x0409, 0):
            priority = 0
        # Macintosh 英文
        elif record.platformID == 1 and record.langID == 0:
            priority = 1
        # Unicode 平台
        elif record.platformID == 0:
            priority = 2

        candidates.append((priority, value))

    if not candidates:
        return None

    candidates.sort(key=lambda item: item[0])
    return candidates[0][1]


def sanitize_filename(value: str) -> str:
    replacements = {
        "苹方-简": "PingFang-SC",
        "蘋方-繁": "PingFang-TC",
        "蘋方-港": "PingFang-HK",
        "苹方": "PingFang",
        "蘋方": "PingFang",
    }

    for source, target in replacements.items():
        value = value.replace(source, target)

    value = value.strip()
    value = re.sub(r"\s+", "-", value)
    value = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "-", value)
    value = re.sub(r"-+", "-", value)

    return value.strip("-. ") or "Unnamed-Font"


def find_collections(search_dir: Path) -> list[Path]:
    """查找当前目录下的 TTC/OTC，不递归进入子目录。"""
    results = [
        path
        for path in search_dir.iterdir()
        if path.is_file() and path.suffix.lower() in {".ttc", ".otc"}
    ]

    return sorted(results, key=lambda path: path.name.lower())


def glyphs_to_quadratic(
    font: TTFont,
    max_error: float,
    reverse_direction: bool = True,
) -> dict[str, object]:
    source_glyphs = font.getGlyphSet()
    quadratic_glyphs: dict[str, object] = {}

    for index, glyph_name in enumerate(source_glyphs.keys(), start=1):
        source_glyph = source_glyphs[glyph_name]

        # TTGlyphPen 接收二次轮廓并生成 glyf 字形。
        tt_pen = TTGlyphPen(source_glyphs)

        # Cu2QuPen 把 CFF 三次曲线转换成 TrueType 二次曲线。
        cu2qu_pen = Cu2QuPen(
            tt_pen,
            max_err=max_error,
            reverse_direction=reverse_direction,
        )

        source_glyph.draw(cu2qu_pen)
        quadratic_glyphs[glyph_name] = tt_pen.glyph()

        if index % 5000 == 0:
            print(f"      已转换 {index} 个字形……")

    return quadratic_glyphs


def update_hmtx(font: TTFont, glyf_table) -> None:
    """
    使用转换后轮廓的 xMin 更新 hmtx 左侧边距。

    这部分逻辑来自 FontTools 官方 otf2ttf 示例。
    """
    hmtx = font["hmtx"]

    for glyph_name, glyph in glyf_table.glyphs.items():
        if hasattr(glyph, "xMin"):
            advance_width = hmtx[glyph_name][0]
            hmtx[glyph_name] = (advance_width, glyph.xMin)


def build_true_type_maxp(font: TTFont, glyf_table) -> None:
    """用 TrueType 1.0 格式重新建立 maxp 表。"""
    maxp = newTable("maxp")
    maxp.tableVersion = 0x00010000

    # 没有生成 TrueType 指令，因此这些值为零。
    maxp.maxZones = 1
    maxp.maxTwilightPoints = 0
    maxp.maxStorage = 0
    maxp.maxFunctionDefs = 0
    maxp.maxInstructionDefs = 0
    maxp.maxStackElements = 0
    maxp.maxSizeOfInstructions = 0

    maxp.maxComponentElements = max(
        (
            len(glyph.components)
            if hasattr(glyph, "components")
            else 0
        )
        for glyph in glyf_table.glyphs.values()
    )

    font["maxp"] = maxp

    # compile 会计算 numGlyphs、maxPoints、maxContours、
    # maxCompositePoints、maxComponentDepth 等字段。
    maxp.compile(font)


def convert_cff_to_truetype(
    font: TTFont,
    max_error: float | None,
) -> None:
    if font.sfntVersion != "OTTO":
        raise ValueError(
            f"该成员不是 CFF OpenType：sfntVersion={font.sfntVersion!r}"
        )

    cff_tag: str

    if "CFF " in font:
        cff_tag = "CFF "
    elif "CFF2" in font:
        cff_tag = "CFF2"
    else:
        raise ValueError("字体中没有 CFF 或 CFF2 表")

    glyph_order = font.getGlyphOrder()
    units_per_em = font["head"].unitsPerEm

    if max_error is None:
        # FontTools 文档推荐接近 UPEM / 1000。
        actual_max_error = units_per_em / 1000
    else:
        actual_max_error = max_error

    print(f"      UPEM：{units_per_em}")
    print(f"      曲线最大误差：{actual_max_error:g} font units")

    quadratic_glyphs = glyphs_to_quadratic(
        font,
        max_error=actual_max_error,
        reverse_direction=True,
    )

    # 创建 TrueType 必需的 loca 和 glyf。
    font["loca"] = newTable("loca")

    glyf = newTable("glyf")
    glyf.glyphOrder = glyph_order
    glyf.glyphs = quadratic_glyphs
    font["glyf"] = glyf

    # 删除原来的 CFF 轮廓。
    del font[cff_tag]

    # VORG 专用于 CFF/CFF2 的竖排原点，不应留在 glyf TTF 中。
    if "VORG" in font:
        del font["VORG"]

    # 先编译 glyf，计算各字形边界。
    glyf.compile(font)

    update_hmtx(font, glyf)
    build_true_type_maxp(font, glyf)

    # 大型 CJK 字体的字形名称经常无法装入 post format 2。
    # format 3 不保存字形名称，兼容性通常更稳。
    if "post" in font:
        post = font["post"]
        post.formatType = 3.0
        post.extraNames = []
        post.mapping = {}
        post.glyphOrder = glyph_order

    # 改成 TrueType sfnt 签名。
    font.sfntVersion = "\x00\x01\x00\x00"

    # 转换过程不生成 TrueType hinting 指令。
    for tag in ("cvt ", "fpgm", "prep", "hdmx", "LTSH"):
        if tag in font:
            del font[tag]

    font.recalcBBoxes = True
    font.recalcTimestamp = False


def verify_ttf(path: Path) -> tuple[bool, str]:
    try:
        font = TTFont(path, lazy=False)

        try:
            tables = set(font.keys())

            required = {
                "head",
                "hhea",
                "maxp",
                "hmtx",
                "cmap",
                "name",
                "post",
                "glyf",
                "loca",
            }

            missing = sorted(required - tables)

            if missing:
                return False, f"缺少表：{', '.join(missing)}"

            if "CFF " in tables or "CFF2" in tables:
                return False, "仍然包含 CFF/CFF2"

            if font.sfntVersion != "\x00\x01\x00\x00":
                return False, (
                    f"sfntVersion 异常：{font.sfntVersion!r}"
                )

            # 强制读取关键表，触发反序列化验证。
            _ = font["glyf"].glyphs
            _ = font["loca"]
            _ = font["cmap"].tables
            _ = font["name"].names

            return True, "TrueType glyf/loca"

        finally:
            font.close()

    except Exception as error:
        return False, str(error)


def unique_output_path(path: Path) -> Path:
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


def convert_collection(
    collection_path: Path,
    output_root: Path,
    max_error: float | None,
) -> tuple[int, int]:
    collection = TTCollection(collection_path, lazy=True)

    try:
        total = len(collection.fonts)
    finally:
        collection.close()

    output_dir = output_root / f"{collection_path.stem}-TTF"
    output_dir.mkdir(parents=True, exist_ok=True)

    print()
    print(f"字体集合：{collection_path}")
    print(f"成员数量：{total}")
    print(f"输出目录：{output_dir}")
    print()

    succeeded = 0
    failed = 0

    for index in range(total):
        font: TTFont | None = None

        try:
            # 每个成员单独打开，避免 24 个大型 CJK 字体同时占用内存。
            font = TTFont(
                collection_path,
                fontNumber=index,
                lazy=False,
                recalcBBoxes=True,
                recalcTimestamp=False,
            )

            postscript_name = get_name(font, 6)
            full_name = get_name(font, 4)
            family_name = get_name(font, 1)
            subfamily_name = get_name(font, 2)

            display_name = (
                postscript_name
                or full_name
                or " ".join(
                    value
                    for value in (family_name, subfamily_name)
                    if value
                )
                or f"Font-{index:02d}"
            )

            output_name = sanitize_filename(display_name)
            output_path = unique_output_path(
                output_dir / f"{output_name}.ttf"
            )

            print(f"[{index + 1:02d}/{total:02d}] {display_name}")

            if "glyf" in font and "CFF " not in font and "CFF2" not in font:
                print("      原成员已经是 TrueType，直接保存。")
            else:
                convert_cff_to_truetype(font, max_error=max_error)

            font.save(output_path, reorderTables=True)
            font.close()
            font = None

            valid, message = verify_ttf(output_path)

            if not valid:
                output_path.unlink(missing_ok=True)
                raise RuntimeError(f"输出验证失败：{message}")

            print(f"      输出：{output_path.name}")
            print(f"      验证：{message}")
            print()

            succeeded += 1

        except Exception as error:
            print(f"      失败：{error}", file=sys.stderr)
            print()
            failed += 1

        finally:
            if font is not None:
                font.close()

    return succeeded, failed


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "查找 TTC/OTC，并使用 FontTools + cu2qu "
            "转换为真正的 TrueType TTF。"
        )
    )

    parser.add_argument(
        "inputs",
        nargs="*",
        type=Path,
        help=(
            "TTC/OTC 文件；不指定时自动查找当前目录。"
        ),
    )

    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path.cwd(),
        help="输出根目录，默认当前目录。",
    )

    parser.add_argument(
        "-e",
        "--max-error",
        type=float,
        default=None,
        help=(
            "曲线最大逼近误差，单位为 font units；"
            "默认使用 UPEM/1000。"
        ),
    )

    arguments = parser.parse_args()

    inputs = [path.expanduser().resolve() for path in arguments.inputs]

    if not inputs:
        inputs = find_collections(Path.cwd())

    if not inputs:
        print(
            "错误：当前目录没有找到 .ttc 或 .otc 文件。",
            file=sys.stderr,
        )
        return 1

    invalid_inputs = [
        path
        for path in inputs
        if not path.is_file()
        or path.suffix.lower() not in {".ttc", ".otc"}
    ]

    if invalid_inputs:
        for path in invalid_inputs:
            print(f"无效输入：{path}", file=sys.stderr)
        return 1

    output_root = arguments.output.expanduser().resolve()
    output_root.mkdir(parents=True, exist_ok=True)

    total_succeeded = 0
    total_failed = 0

    for collection_path in inputs:
        succeeded, failed = convert_collection(
            collection_path,
            output_root,
            max_error=arguments.max_error,
        )

        total_succeeded += succeeded
        total_failed += failed

    print("全部处理完成：")
    print(f"  成功：{total_succeeded}")
    print(f"  失败：{total_failed}")
    print(f"  输出根目录：{output_root}")

    return 1 if total_failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
