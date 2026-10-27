#!/usr/bin/env python3
"""Entry 한글 폰트를 지정한 저장소 외부 폴더에 재현하고 원본·glyph를 검증합니다."""

import argparse
import hashlib
import importlib.metadata
import json
import tempfile
import urllib.request
from pathlib import Path


COMMIT = "4efc2774c63917927efe769ca845def6bd6debae"
BASE_URL = f"https://raw.githubusercontent.com/google/fonts/{COMMIT}/ofl/notosanskr"
FONT_URL = BASE_URL + "/NotoSansKR%5Bwght%5D.ttf"
OFL_URL = BASE_URL + "/OFL.txt"
SOURCE_SHA = "194018e6b2b293a7964f037b25c0249ce1418bc9ab3c971060a03aa57861e252"
OFL_SHA = "1c05c68c34f9708415aada51f17e1b0092d2cea709bf4a94cd38114f9e73d7d9"
FONTTOOLS_VERSION = "4.60.2"
FAMILY = "Labcord Entry Hangul"
REPO_ROOT = Path(__file__).resolve().parents[2]
RANGES = [(0x0020, 0x0020), (0xAC00, 0xD7A3), (0x1100, 0x11FF),
          (0x3130, 0x318F), (0xA960, 0xA97F), (0xD7B0, 0xD7FF),
          (0xFFA0, 0xFFDC)]
UNICODES = sorted({cp for lo, hi in RANGES for cp in range(lo, hi + 1)})
PRESERVED_NAME_IDS = [0, 5, 13, 14]
EXPECTED_OUTPUT_SHA = {
    "Regular": "75468a2a640001c36adbfef4074ce985953d7376812efbf969631239cd4c84a2",
    "Medium": "b4c2063be71949f1040b08a359376471876fe8f9fc0ca399e5e147b20c0b9346",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def output_path(root, relative):
    path = root / relative
    resolved = path.resolve()
    require(resolved.is_relative_to(root) and not resolved.is_relative_to(REPO_ROOT),
            f"출력 폴더 밖을 가리키는 경로입니다: {path}")
    return path


def ensure_source(path, url, expected):
    if path.exists():
        require(sha(path) == expected, f"기존 원본의 SHA256이 다릅니다: {path}")
        return
    temporary = None
    try:
        with urllib.request.urlopen(url, timeout=60) as response:
            with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as download:
                temporary = Path(download.name)
                while chunk := response.read(1024 * 1024):
                    download.write(chunk)
        require(sha(temporary) == expected, f"다운로드 원본의 SHA256이 다릅니다: {url}")
        temporary.replace(path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def preserved_names(font):
    return {str(i): [n.toUnicode() for n in font["name"].names if n.nameID == i]
            for i in PRESERVED_NAME_IDS}


def rename(font, style):
    # 저작권(0), 버전(5), 라이선스(13/14)는 원본 그대로 보존합니다.
    names = {1: FAMILY, 2: style, 3: f"2.004-H2;LabcordEntryHangul;{style}",
             4: FAMILY + " " + style, 6: "LabcordEntryHangul-" + style,
             16: FAMILY, 17: style}
    for record in font["name"].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())
    for name_id, value in names.items():
        font["name"].setName(value, name_id, 3, 1, 0x409)
    font["OS/2"].usWeightClass = 400 if style == "Regular" else 500
    font["OS/2"].fsSelection &= ~(1 << 0 | 1 << 5)
    font["OS/2"].fsSelection |= 1 << 6
    font["head"].macStyle &= ~3


def glyph_signature(font, name):
    glyph = font["glyf"][name]
    coords, ends, flags = glyph.getCoordinates(font["glyf"])
    instructions = list(glyph.program.getBytecode()) if hasattr(glyph, "program") else []
    components = [(part.glyphName, part.getComponentInfo()[1], part.flags)
                  for part in glyph.components] if glyph.isComposite() else []
    return (list(coords), list(ends), list(flags), instructions, components,
            font["hmtx"][name], font["vmtx"][name] if "vmtx" in font else None)


def prepare(root):
    # --help와 출력 경로 검사는 fontTools 설치 없이 실행할 수 있습니다.
    try:
        version = importlib.metadata.version("fonttools")
    except importlib.metadata.PackageNotFoundError as error:
        raise ValueError("외부 venv에 fonttools==4.60.2를 설치해야 합니다.") from error
    require(version == FONTTOOLS_VERSION,
            f"fontTools {FONTTOOLS_VERSION}가 필요합니다. 현재 버전: {version}")
    from fontTools import subset
    from fontTools.ttLib import TTFont
    from fontTools.varLib.instancer import instantiateVariableFont

    # 기존 하위 폴더가 외부 symlink이면 다운로드·생성 전에 거절합니다.
    for relative in ["source", "work", "fonts", "source/NotoSansKR-variable.ttf",
                     "OFL.txt", "manifest.json"]:
        output_path(root, relative)
    for directory in ["source", "work", "fonts"]:
        output_path(root, directory).mkdir(parents=True, exist_ok=True)
    source_path = output_path(root, "source/NotoSansKR-variable.ttf")
    ensure_source(source_path, FONT_URL, SOURCE_SHA)
    ensure_source(output_path(root, "OFL.txt"), OFL_URL, OFL_SHA)
    with TTFont(source_path, recalcTimestamp=False) as source:
        original_names = preserved_names(source)
    manifest = {
        "sourceCommit": COMMIT, "sourceURL": FONT_URL, "licenseURL": OFL_URL,
        "sourceSHA256": SOURCE_SHA, "licenseSHA256": OFL_SHA,
        "fontToolsVersion": version, "family": FAMILY,
        "unicodeRanges": [f"U+{lo:04X}-{hi:04X}" for lo, hi in RANGES],
        "coordinatePolicy": "고정 weight를 인스턴스화한 후 glyph를 변형하지 않는다. "
                            "Figma 비교용 중간점 정수 내림은 폰트에 적용하지 않는다.",
        "originalNamesPreserved": original_names, "fonts": [],
    }
    for style, weight in [("Regular", 400), ("Medium", 500)]:
        font = instantiateVariableFont(TTFont(source_path, recalcTimestamp=False),
                                       {"wght": weight}, inplace=True, optimize=False)
        font.recalcTimestamp = False
        rename(font, style)
        # 서브셋의 GID 변경과 무관하게 glyph 이름을 보존해 전체 윤곽을 비교합니다.
        font["post"].formatType = 2.0
        font["post"].extraNames = []
        font["post"].mapping = {}
        full_path = output_path(root, f"work/LabcordEntryHangul-{style}-full.ttf")
        font.save(full_path)
        font.close()
        full = TTFont(full_path, recalcTimestamp=False)
        options = subset.Options()
        options.hinting = True
        options.notdef_glyph = True
        options.notdef_outline = True
        options.recommended_glyphs = False
        options.glyph_names = True
        options.name_IDs = ["*"]
        options.name_legacy = True
        options.name_languages = ["*"]
        options.recalc_timestamp = False
        subsetter = subset.Subsetter(options=options)
        subsetter.populate(unicodes=UNICODES)
        candidate = TTFont(full_path, recalcTimestamp=False)
        subsetter.subset(candidate)
        candidate.recalcTimestamp = False
        path = output_path(root, f"fonts/LabcordEntryHangul-{style}.ttf")
        candidate.save(path)
        candidate.close()
        result = TTFont(path, recalcTimestamp=False)
        cmap, full_cmap = result.getBestCmap(), full.getBestCmap()
        expected_cmap = {cp for cp in UNICODES if cp in full_cmap}
        require(set(cmap) == expected_cmap, f"문자 범위가 다릅니다: {style}")
        require(all(cmap[cp] == full_cmap[cp] for cp in expected_cmap),
                f"문자와 glyph의 대응이 바뀌었습니다: {style}")
        require(result.getGlyphOrder()[0] == ".notdef", f".notdef 누락: {style}")
        require(set(result.getGlyphOrder()).issubset(full.getGlyphOrder()),
                f"참조 원본에 없는 glyph입니다: {style}")
        changed = [name for name in result.getGlyphOrder()
                   if glyph_signature(result, name) != glyph_signature(full, name)]
        require(not changed, f"glyph 좌표·메트릭·힌팅이 바뀌었습니다: {changed[:20]}")
        require(preserved_names(result) == original_names,
                f"저작권·버전·라이선스가 바뀌었습니다: {style}")
        hints = [tag for tag in ["cvt ", "fpgm", "prep", "gasp"] if tag in full]
        require(all(tag in result and result[tag].compile(result) == full[tag].compile(full)
                    for tag in hints), f"힌팅 테이블이 바뀌었습니다: {style}")
        require(sha(path) == EXPECTED_OUTPUT_SHA[style],
                f"기준 시안과 출력 SHA256이 다릅니다: {style}")
        item = {
            "style": style, "weight": weight, "file": str(path.relative_to(root)),
            "bytes": path.stat().st_size, "sha256": sha(path),
            "fullReferenceFile": str(full_path.relative_to(root)),
            "fullReferenceBytes": full_path.stat().st_size,
            "fullReferenceSHA256": sha(full_path),
            "glyphCount": len(result.getGlyphOrder()), "unicodeCount": len(cmap),
            "allRetainedGlyphsCoordinatesMetricsHintingIdentical": True,
            "preservedHintingTables": hints,
            "rangeCoverage": {f"U+{lo:04X}-{hi:04X}":
                              sum(cp in cmap for cp in range(lo, hi + 1))
                              for lo, hi in RANGES},
            "sourceMissingRequestedCodepoints": [f"U+{cp:04X}" for cp in UNICODES
                                                 if cp not in full_cmap],
            "names": {str(i): sorted({n.toUnicode() for n in result["name"].names
                                       if n.nameID == i})
                      for i in [0, 1, 2, 4, 5, 6, 13, 14, 16, 17]},
        }
        manifest["fonts"].append(item)
        print(f"{path.name}: {item['bytes']} bytes, SHA256 {item['sha256']}", flush=True)
        full.close()
        result.close()
    output_path(root, "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="원본·작업 파일·결과를 생성할 저장소 외부 폴더")
    args = parser.parse_args()
    root = args.output.expanduser().resolve()
    if root == REPO_ROOT or root.is_relative_to(REPO_ROOT):
        parser.error("저장소 내부에는 생성하지 않습니다. 외부 출력 폴더를 지정하세요.")
    try:
        prepare(root)
    except (OSError, ValueError) as error:
        parser.exit(1, f"폰트 준비 실패: {error}\n")


if __name__ == "__main__":
    main()
