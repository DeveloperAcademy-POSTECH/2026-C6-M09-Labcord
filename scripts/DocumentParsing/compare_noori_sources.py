"""공개 누리 원본 XML을 실제 파싱 JSON과 대조한다. 문서를 네트워크로 보내지 않는다."""

import argparse
import collections
import hashlib
import json
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'ResearchersTests/Fixtures/RealWorld'
NS = {'p': 'http://www.hancom.co.kr/hwpml/2011/paragraph'}


def compact(text):
    return ''.join(text.split())


def compare(parsed_directory):
    source = FIXTURES / 'hwpx/real-hwpx-02-noori.hwpx'
    with zipfile.ZipFile(source) as archive:
        section = ET.fromstring(archive.read('Contents/section0.xml'))
        texts = [''.join(t.itertext()) for t in section.findall('.//p:t', NS)
                 if ''.join(t.itertext()).strip()]
        images = [name for name in archive.namelist() if name.startswith('BinData/')]
    results = [json.loads((parsed_directory / f'{name}.json').read_text())
               for name in ('hwp-01-noori', 'hwpx-02-noori')]
    report = {
        'sourceSHA256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'sourceTextRuns': len(texts),
        'sourceTables': len(section.findall('.//p:tbl', NS)),
        'sourceCellsIncludingEmptyAndPictureOnly': len(section.findall('.//p:tc', NS)),
        'sourceEmbeddedImages': len(images),
        'documents': [],
    }
    native = []
    for result in results:
        native.append([(b['kind'], compact(b['text']), b.get('location', {}))
                       for b in result['blocks'] if b['kind'] != 'imageOCR'])
        warnings = result['warnings']
        report['documents'].append({
            'id': result['id'],
            'missingSourceTextRunIndices': [i for i, text in enumerate(texts)
                                           if compact(text) not in compact(result['fullText'])],
            'blockKinds': dict(collections.Counter(b['kind'] for b in result['blocks'])),
            'images': len(result['images']),
            'warningCodes': dict(collections.Counter(w['code'] for w in warnings)),
            'warningDocInfo': sum(w.get('location', {}).get('part', '').startswith('docInfo')
                                  for w in warnings),
            'warningSection': sum(w.get('location', {}).get('part', '').startswith('section')
                                  for w in warnings),
        })
    report['nativeBlocksEqual'] = native[0] == native[1]
    report['ocrTextMultisetEqual'] = all(
        collections.Counter(b['text'] for b in results[0]['blocks'] if b['kind'] == 'imageOCR')
        == collections.Counter(b['text'] for b in result['blocks'] if b['kind'] == 'imageOCR')
        for result in results[1:])
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('parsed_directory', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(compare(args.parsed_directory), ensure_ascii=False, indent=2)
                           + '\n')
