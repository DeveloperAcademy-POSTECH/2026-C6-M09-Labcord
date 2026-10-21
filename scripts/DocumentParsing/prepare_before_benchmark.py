"""개선 전 코드를 새 임시 사본에 재현한다. 현재 작업 트리는 변경하지 않는다."""

import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASELINE = ROOT / 'docs' / 'LabcordParser' / 'Benchmarks'


def prepare(output, baseline='initial'):
    destination = Path(output).expanduser().resolve()
    if destination.exists():
        raise FileExistsError(f'기존 경로를 덮어쓰지 않습니다: {destination}')
    if destination == ROOT or ROOT in destination.parents:
        raise ValueError('저장소 밖의 새 임시 경로를 지정하세요')
    destination.mkdir(parents=True)
    for name in ['Researchers', 'ResearchWatch Watch App', 'ResearchersTests',
                 'Researchers.xcodeproj']:
        shutil.copytree(ROOT / name, destination / name,
                        ignore=shutil.ignore_patterns('xcuserdata', '.DS_Store'))
    patch = 'restore-before.patch' if baseline == 'initial' else 'restore-before-memory-peak.patch'
    manifest = ('Before-Source-SHA256.json' if baseline == 'initial'
                else 'Memory-Peak-Before-Source-SHA256.json')
    subprocess.run(['git', 'apply', str(BASELINE / patch)],
                   cwd=destination, check=True)
    source = destination / 'Researchers' / 'Services' / 'DocumentParsing'
    expected = json.loads((BASELINE / manifest).read_text())
    actual = {str(path.relative_to(source)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in source.rglob('*.swift')}
    if actual != expected:
        raise ValueError('개선 전 파서 소스의 파일 집합 또는 해시가 다릅니다')
    tests = destination / 'ResearchersTests'
    for relative in ['DocumentParsing/Images/DocumentOCRSessionPoolTests.swift',
                     'DocumentParsing/PDF/DocumentPDFMemoryBudgetTests.swift']:
        (tests / relative).unlink(missing_ok=True)
    if baseline == 'initial':
        for name in ['DocumentPDFWorkPoolTests.swift', 'DocumentPDFPNGEncoderTests.swift',
                     'DocumentPDFParallelTests.swift', 'DocumentPDFRecognitionReuseTests.swift']:
            (tests / 'DocumentParsing' / 'PDF' / name).unlink()
        helper = tests / 'Support' / 'PDF' / 'DocumentScanStressSupport.swift'
        text = helper.read_text()
        start = text.index('      if let batch = metrics.batchScheduling {')
        end = text.index('      row["pdfWallSeconds"]', start)
        helper.write_text(text[:start] + text[end:])
    print(f'개선 전 파서 {len(actual)}개 파일의 해시 확인: {destination}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('--baseline', choices=['initial', 'memory-peak'], default='initial')
    args = parser.parse_args()
    prepare(args.output, args.baseline)
