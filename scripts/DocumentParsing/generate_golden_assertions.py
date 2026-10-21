"""원본 XML과 기존 수동 대조 문구로 부분 정답을 재생성한다. 파서 출력은 읽지 않는다."""

import json
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'ResearchersTests/Fixtures/RealWorld'


def hwpx_assertions(path):
    ns = {'p': 'http://www.hancom.co.kr/hwpml/2011/paragraph'}
    cells, runs = [], []
    with zipfile.ZipFile(path) as archive:
        sections = sorted(name for name in archive.namelist()
                          if name.startswith('Contents/section') and name.endswith('.xml'))
        for name in sections:
            section = ET.fromstring(archive.read(name))
            runs.extend(''.join(t.itertext()) for t in section.findall('.//p:t', ns)
                        if ''.join(t.itertext()).strip())
            for table in section.findall('.//p:tbl', ns):
                for cell in table.findall('./p:tr/p:tc', ns):
                    text = '\n'.join(''.join(t.itertext())
                                     for t in cell.findall('.//p:t', ns)).strip()
                    address = cell.find('p:cellAddr', ns)
                    span = cell.find('p:cellSpan', ns)
                    if text and address is not None:
                        cells.append({'row': int(address.get('rowAddr')) + 1,
                                      'column': int(address.get('colAddr')) + 1, 'text': text,
                                      'rowSpan': int(span.get('rowSpan', '1')) if span is not None else 1,
                                      'columnSpan': int(span.get('colSpan', '1')) if span is not None else 1})
    return cells, runs


def pptx_cells(path):
    ns = {'a': 'http://schemas.openxmlformats.org/drawingml/2006/main'}
    cells = []
    with zipfile.ZipFile(path) as archive:
        slides = sorted(name for name in archive.namelist()
                        if name.startswith('ppt/slides/slide') and name.endswith('.xml'))
        for name in slides:
            slide = ET.fromstring(archive.read(name))
            for table in slide.findall('.//a:tbl', ns):
                for row, tr in enumerate(table.findall('a:tr', ns), 1):
                    for column, cell in enumerate(tr.findall('a:tc', ns), 1):
                        text = ''.join(t.text or '' for t in cell.findall('.//a:t', ns))
                        if text:
                            cells.append({'row': row, 'column': column, 'text': text})
    return cells


def generate():
    manifest = json.loads((FIXTURES / 'RealWorldManifest.json').read_text())
    goldens = []
    for fixture in manifest:
        entry = {
            'id': fixture['id'], 'sha256': fixture['sha256'],
            'textAnchors': fixture['expectedText'], 'orderedText': [], 'cells': [],
            'sourceTextRuns': [], 'evidence': '기존 원본 대조 문구; 전체 문서 정답은 아님',
        }
        path = FIXTURES / fixture['format'] / fixture['filename']
        if fixture['format'] == 'hwpx':
            entry['cells'], entry['sourceTextRuns'] = hwpx_assertions(path)
            entry['evidence'] = '원본 HWPX section XML의 hp:t 및 cellAddr; 공백만 정규화'
        if fixture['id'] in {'hwp-01-noori', 'hwpx-02-noori'}:
            entry['exactImages'] = 4
        if fixture['id'] == 'real-doc-02':
            entry['cells'] = [{'row': row, 'column': column, 'text': f'Cell {row},{column}'}
                              for row in (1, 2) for column in (1, 2, 3)]
            entry['orderedText'] = ['This is a Word document'] + [
                cell['text'] for cell in entry['cells']]
            entry['evidence'] = '원문에서 명시한 2행 3열 및 셀 라벨'
        if fixture['id'] == 'real-pptx-02':
            entry['cells'] = pptx_cells(path)
            entry['orderedText'] = [cell['text'] for cell in entry['cells']]
            entry['evidence'] = '원본 PPTX slide XML의 표 행·셀·텍스트'
        if fixture['id'] == 'real-pdf-03':
            entry['orderedText'] = ['Left column line 1', 'Right column line 1',
                                    'Left column line 2', 'Right column line 2']
            entry['evidence'] = '원본 PDF 행 기준 위→아래·왼쪽→오른쪽 순서; 단 기준 읽기 정책과 구분'
        if fixture['id'] == 'real-ppt-02':
            entry['exactImages'] = 2
        goldens.append(entry)
    # 동일 문서의 XML 근거를 HWP에도 적용한다. 바이너리 조판 전체의 정답은 아니다.
    hwp = next(entry for entry in goldens if entry['id'] == 'hwp-01-noori')
    hwpx = next(entry for entry in goldens if entry['id'] == 'hwpx-02-noori')
    hwp.update(cells=hwpx['cells'], sourceTextRuns=hwpx['sourceTextRuns'],
               evidence='동일 누리 보도자료의 HWPX XML 대조; HWP 바이너리 전체 조판 정답은 아님')
    (FIXTURES / 'GoldenAssertions.json').write_text(
        json.dumps(goldens, ensure_ascii=False, indent=2) + '\n')
    print(f"goldens {len(goldens)}, cells {sum(len(g['cells']) for g in goldens)}, "
          f"runs {sum(len(g['sourceTextRuns']) for g in goldens)}")


if __name__ == '__main__':
    generate()
