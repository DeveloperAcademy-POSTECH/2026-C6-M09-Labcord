#!/usr/bin/env python3
"""Figma 원본과 Simulator PNG의 원시 RGB·alpha를 표준 라이브러리만으로 비교합니다.

8bit RGB/RGBA, 비인터레이스 PNG만 지원하며 모든 chunk CRC와 행 필터를 검증합니다.
색상 변환·alpha 합성·정렬·크기 변경·마스크·임계치를 적용하지 않습니다.
픽셀 차이가 있어도 분석 성공은 종료 코드 0입니다. pixelsIdentical로 동일 여부를 확인합니다.
손상·미지원 형식·크기 불일치·불투명하지 않은 입력·출력 오류는 종료 코드 1입니다.
"""

import argparse
import hashlib
import json
import struct
import sys
import zlib
from pathlib import Path


SIGNATURE = b"\x89PNG\r\n\x1a\n"
REPO_ROOT = Path(__file__).resolve().parents[2]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def paeth(left, above, upper_left):
    prediction = left + above - upper_left
    distances = (abs(prediction - left), abs(prediction - above),
                 abs(prediction - upper_left))
    if distances[0] <= distances[1] and distances[0] <= distances[2]:
        return left
    return above if distances[1] <= distances[2] else upper_left


def decode_png(data, name):
    require(data.startswith(SIGNATURE), f"PNG 서명이 올바르지 않습니다: {name}")
    offset, header, transparent = len(SIGNATURE), None, None
    compressed, seen, filters = [], set(), {str(i): 0 for i in range(5)}
    idat_ended, ended, chunks = False, False, 0
    while offset < len(data):
        require(offset + 12 <= len(data), f"잘린 PNG chunk입니다: {name}")
        length, kind = struct.unpack_from(">I4s", data, offset)
        require(length <= 0x7FFFFFFF and offset + 12 + length <= len(data),
                f"PNG chunk 길이가 올바르지 않습니다: {name}")
        require(all(65 <= c <= 90 or 97 <= c <= 122 for c in kind)
                and not kind[2] & 32, f"PNG chunk 이름이 올바르지 않습니다: {name}")
        payload = data[offset + 8:offset + 8 + length]
        expected_crc = struct.unpack_from(">I", data, offset + 8 + length)[0]
        actual_crc = zlib.crc32(payload, zlib.crc32(kind)) & 0xFFFFFFFF
        require(actual_crc == expected_crc,
                f"{kind.decode('ascii')} CRC가 다릅니다: {name}")
        offset += length + 12
        chunks += 1
        require(header is not None or kind == b"IHDR", f"첫 chunk가 IHDR이 아닙니다: {name}")
        if kind != b"IDAT" and compressed:
            idat_ended = True
        if kind == b"IHDR":
            require(header is None and length == 13, f"IHDR이 중복되거나 잘못됐습니다: {name}")
            header = struct.unpack(">IIBBBBB", payload)
            width, height, depth, color, compression, filtering, interlace = header
            require(0 < width <= 0x7FFFFFFF and 0 < height <= 0x7FFFFFFF,
                    f"PNG 크기가 올바르지 않습니다: {name}")
            require(depth == 8 and color in (2, 6),
                    f"8bit RGB/RGBA PNG만 지원합니다 (depth={depth}, color={color}): {name}")
            require(compression == 0 and filtering == 0 and interlace == 0,
                    f"표준 압축·필터의 비인터레이스 PNG만 지원합니다: {name}")
        elif kind == b"PLTE":
            require(kind not in seen and not compressed and 0 < length <= 768 and length % 3 == 0,
                    f"PLTE 형식·순서가 올바르지 않습니다: {name}")
        elif kind == b"tRNS":
            require(kind not in seen and not compressed and color == 2 and length == 6,
                    f"tRNS 형식·순서가 올바르지 않습니다: {name}")
            transparent = struct.unpack(">HHH", payload)
            require(all(value <= 255 for value in transparent), f"8bit tRNS 값이 아닙니다: {name}")
        elif kind == b"IDAT":
            require(not idat_ended, f"IDAT chunk가 연속되지 않습니다: {name}")
            compressed.append(payload)
        elif kind == b"IEND":
            require(length == 0 and compressed and offset == len(data),
                    f"IEND가 잘못됐거나 뒤에 데이터가 있습니다: {name}")
            ended = True
            break
        elif not kind[0] & 32:
            raise ValueError(f"지원하지 않는 필수 chunk {kind.decode('ascii')}: {name}")
        seen.add(kind)
    require(ended, f"IEND가 없습니다: {name}")
    channels = 3 if color == 2 else 4
    stride = width * channels
    expected_size = (stride + 1) * height
    require(expected_size < sys.maxsize, f"PNG 크기가 처리 범위를 넘습니다: {name}")
    inflater = zlib.decompressobj()
    raw = inflater.decompress(b"".join(compressed), expected_size + 1)
    require(len(raw) == expected_size and inflater.eof
            and not inflater.unused_data and not inflater.unconsumed_tail,
            f"IDAT 압축 데이터 또는 해제 길이가 올바르지 않습니다: {name}")
    previous, rgb, alpha = bytearray(stride), bytearray(), bytearray()
    for y in range(height):
        start = y * (stride + 1)
        filter_type = raw[start]
        require(filter_type <= 4, f"지원하지 않는 행 필터 {filter_type}, 행 {y}: {name}")
        filters[str(filter_type)] += 1
        row = bytearray(raw[start + 1:start + 1 + stride])
        if filter_type:
            for x in range(stride):
                left = row[x - channels] if x >= channels else 0
                above = previous[x]
                upper_left = previous[x - channels] if x >= channels else 0
                if filter_type == 1:
                    predictor = left
                elif filter_type == 2:
                    predictor = above
                elif filter_type == 3:
                    predictor = (left + above) // 2
                else:
                    predictor = paeth(left, above, upper_left)
                row[x] = (row[x] + predictor) & 255
        if channels == 3:
            rgb.extend(row)
            row_alpha = bytearray(b"\xff" * width)
            if transparent is not None:
                for x in range(width):
                    if tuple(row[x * 3:x * 3 + 3]) == transparent:
                        row_alpha[x] = 0
            alpha.extend(row_alpha)
        else:
            row_rgb = bytearray(width * 3)
            for channel in range(3):
                row_rgb[channel::3] = row[channel::4]
            rgb.extend(row_rgb)
            alpha.extend(row[3::4])
        previous = row
    nonopaque = len(alpha) - alpha.count(255)
    return {
        "rgb": bytes(rgb), "alpha": bytes(alpha),
        "metadata": {"path": str(name), "sha256": hashlib.sha256(data).hexdigest(),
                     "dimensions": [width, height], "bit_depth": depth,
                     "color_type": "RGB" if color == 2 else "RGBA", "interlaced": False,
                     "crc_verified_chunks": chunks, "row_filters": filters,
                     "alpha_range": [min(alpha), max(alpha)],
                     "opaque": nonopaque == 0, "nonopaque_pixels": nonopaque},
    }


def compare(reference, candidate):
    reference_meta, candidate_meta = reference["metadata"], candidate["metadata"]
    report = {"status": "compared", "reference": reference_meta, "candidate": candidate_meta,
              "reference_sha256": reference_meta["sha256"],
              "candidate_sha256": candidate_meta["sha256"],
              "alignment": None, "mask": None, "threshold": None,
              "color_conversion": None, "alpha_compositing": None}
    if reference_meta["dimensions"] != candidate_meta["dimensions"]:
        report.update(status="error", error="PNG 크기가 다릅니다. 크기 변경 없이 비교할 수 없습니다.")
        return report, 1
    left, right = reference["rgb"], candidate["rgb"]
    total_pixels = len(left) // 3
    different, total_difference, maximum = 0, 0, 0
    for index in range(0, len(left), 3):
        delta = [abs(left[index + channel] - right[index + channel]) for channel in range(3)]
        different += any(delta)
        total_difference += sum(delta)
        maximum = max(maximum, *delta)
    alpha_mismatch = sum(a != b for a, b in zip(reference["alpha"], candidate["alpha"]))
    report.update(dimensions=reference_meta["dimensions"], total_pixels=total_pixels,
                  different_pixels=different, percent_different=100 * different / total_pixels,
                  mae=total_difference / (total_pixels * 3),
                  max_channel_difference=maximum, alpha_mismatch_pixels=alpha_mismatch,
                  pixelsIdentical=different == 0 and alpha_mismatch == 0)
    if reference_meta["nonopaque_pixels"] or candidate_meta["nonopaque_pixels"]:
        report.update(status="error", error="완전히 불투명한 PNG가 아닙니다. alpha 합성 없이 원시값만 보고합니다.")
        return report, 1
    return report, 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path, help="Figma 원본 3x PNG")
    parser.add_argument("candidate", type=Path, help="Simulator에서 얻은 원시 PNG")
    parser.add_argument("--output", type=Path,
                        help="새 JSON 보고서의 저장소 외부 경로. 생략하면 stdout에 출력하며 기존 파일은 덮지 않습니다.")
    args = parser.parse_args()
    output = None
    try:
        output = args.output.expanduser().resolve() if args.output else None
        if output is not None:
            require(not output.is_relative_to(REPO_ROOT), "보고서는 저장소 외부에만 저장할 수 있습니다.")
            require(not output.exists(), f"기존 보고서를 덮지 않습니다: {output}")
    except (OSError, ValueError, RuntimeError) as error:
        print(json.dumps({"status": "error", "error": str(error)}, ensure_ascii=False, indent=2))
        return 1
    try:
        reference = args.reference.expanduser().resolve()
        candidate = args.candidate.expanduser().resolve()
        report, result = compare(decode_png(reference.read_bytes(), reference),
                                 decode_png(candidate.read_bytes(), candidate))
    except (OSError, ValueError, zlib.error) as error:
        report, result = {"status": "error", "error": str(error)}, 1
    content = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    try:
        if args.output:
            require(output is not None and not output.is_relative_to(REPO_ROOT),
                    "보고서는 저장소 외부에만 저장할 수 있습니다.")
            with output.open("x", encoding="utf-8") as target:
                target.write(content)
        else:
            print(content, end="")
    except (OSError, ValueError) as error:
        print(f"PNG 비교 보고서 출력 실패: {error}", file=sys.stderr)
        return 1
    return result


if __name__ == "__main__":
    raise SystemExit(main())
