"""외부 검증 자산의 수량, 출처 메타데이터, 원본 해시를 오프라인으로 확인한다."""

import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
FIXTURES = ROOT / 'ResearchersTests' / 'Fixtures' / 'RealWorld'
FORMATS = {
    'txt', 'csv', 'json', 'xml', 'jpeg', 'png', 'heic', 'tiff', 'pdf',
    'docx', 'xlsx', 'pptx', 'hwp', 'hwpx', 'rtf', 'html', 'markdown',
    'doc', 'xls', 'ppt',
}


def verify():
    entries = json.loads((FIXTURES / 'RealWorldManifest.json').read_text())
    counts = Counter(entry['format'] for entry in entries)
    assert set(counts) == FORMATS, f'형식 불일치: {set(counts) ^ FORMATS}'
    assert all(count == 3 for count in counts.values()), counts
    assert len({entry['id'] for entry in entries}) == len(entries), '중복 ID'
    assert len({entry['filename'] for entry in entries}) == len(entries), '중복 파일명'
    total = 0
    for entry in entries:
        name = entry['filename']
        assert Path(name).name == name, f'파일명에 경로 포함: {name}'
        matches = list(FIXTURES.rglob(name))
        assert len(matches) == 1, f'파일 누락 또는 중복: {name}'
        data = matches[0].read_bytes()
        assert hashlib.sha256(data).hexdigest() == entry['sha256'], f'해시 불일치: {name}'
        assert entry['sourceURL'].startswith('https://'), entry['id']
        assert entry['licenseEvidenceURL'].startswith('https://'), entry['id']
        assert entry['license'] and entry['licenseReason'], entry['id']
        assert entry['minimumTextLength'] >= 0, entry['id']
        total += len(data)
    for fmt in sorted(FORMATS):
        hashes = {entry['sha256'] for entry in entries if entry['format'] == fmt}
        assert len(hashes) == 3, f'동일 원본 중복: {fmt}'
    print(f'{len(entries)} files, {len(counts)} formats, {total:,} bytes: verified')
    large = json.loads((FIXTURES / 'LargeScans' / 'Manifest.json').read_text())
    for entry in large:
        name = entry['filename']
        assert Path(name).name == name, f'파일명에 경로 포함: {name}'
        data = (FIXTURES / 'LargeScans' / name).read_bytes()
        assert hashlib.sha256(data).hexdigest() == entry['sha256'], f'해시 불일치: {name}'
        assert len(data) == entry['sizeBytes'], f'크기 불일치: {name}'
        assert entry['licenseEvidenceURL'].startswith('https://'), name
        assert entry['sourceURL'].startswith('https://'), name
    print(f'{len(large)} additional original large-scan PDFs: verified')


if __name__ == '__main__':
    verify()
