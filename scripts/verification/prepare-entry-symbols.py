#!/usr/bin/env python3
"""기존 SVG에서 고정16표본 template PNG를 저장소 외부에 재현합니다."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import platform
import re
import runpy
import shutil
import subprocess
import tempfile
import uuid
import xml.etree.ElementTree as ET

SELECTED = [1, 5, 11, 15, 16, 20, 26, 30, 33, 37, 43, 47, 48, 52, 58, 62]
SOURCES = {
    'gear': (48, [11.6484375, 11.66357421875],
             'd0a28750623adec300d1e5901840b1fb12f4c97ff13db78ab9df370bbf3b5564'),
    'plus': (48, [15.134765625, 15.1416015625],
             'e29279e2ea58e5fd275d5fe683e8e874f34c63a800af14cdafcbd32f9ebcb20f'),
    'back': (44, [15.29296875, 12.7431640625],
             '1a92bf7a245cf55ac59745d295d15da25ec9a06532d4cf025ab14be63a03d40c'),
}
EXPECTED = {'gear@1x': {'alphaSHA256': 'a8b3e5e688e36c905b2ed6f8004b6065771ed01238dd738bedeafb5ccf708f35',
             'PNGSHA256': '92470154ce5e839d56b9b7a1972f5a8958d174e4f4369f35b13106aea04dddda'},
 'plus@1x': {'alphaSHA256': 'dd0a00ee852cd33932746b743b216fab0375467937939d746189918ac2c06380',
             'PNGSHA256': '37c2189da6b9bf2a99093d5bfb3574035dc61098bd9c73260c265a20785756a6'},
 'back@1x': {'alphaSHA256': '0e5cdb8267987f84a86c475b7ef8f1e79388cd34d6cbf0c2078550b69206fdcf',
             'PNGSHA256': '51e4f00d859e7683dc71329682e346eba0fe8fa03a82db43bbc12372db31b94d'},
 'gear@2x': {'alphaSHA256': '7e72ede2050c7342ba8680f2da2fbe9920f8df351ccf1adab69f608e1da3eb6d',
             'PNGSHA256': 'b635469c95a14dc9753dc31db71c09a7eda0144614fc9fea8e91238e0cc53b69'},
 'plus@2x': {'alphaSHA256': 'eecd22767a5da85d3f4a7f98956e21fdceb4ff2b6f90b600ec795ff1a26b8aa2',
             'PNGSHA256': 'fe2e0e587f9a60db8fe9c8073655992e31aa8cb8560f97c96a9b9567ca68f25d'},
 'back@2x': {'alphaSHA256': 'b31aedeb79cc8203164ac3e49dbdbe699c2a994f907dbf6b05509dcf3c02bab3',
             'PNGSHA256': '357170f15f1b81e8b19ce73972e27415cafb20488b65030ade204d644046775f'},
 'gear@3x': {'alphaSHA256': 'c6a4e69610e5a1a16c744c3f6bf86a4914c2c3886ed7f88755a6018e1f1ed1e0',
             'PNGSHA256': '42a6df64b2c91c6d2c6bcb2a34aa32fb3dadf51343c0f41789ecfd5a8f3e45e5'},
 'plus@3x': {'alphaSHA256': 'c8bf3339415018395d9cc3b5a5ba0b5d548fc17d3e82663b6cf41728698c3445',
             'PNGSHA256': '811198c9bd19a9691276c1a456ae4103f5ed825237cf21ab2a081348565d97ba'},
 'back@3x': {'alphaSHA256': '3751528124dea70fc2feb5610caffb7f8135909243ac02c320ebfee3b64e1164',
             'PNGSHA256': 'caa654d0b56af1070349ef2130cf2a4eba4851cbee659231efe88762d0c779a1'}}
TOKEN = re.compile(r'[A-Za-z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?')


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def run(arguments, timeout=30):
    return subprocess.run(arguments, check=True, capture_output=True, text=True,
                          timeout=timeout).stdout.strip()


def parse_path(value):
    """기존 exact parser: H/V는 같은 절대좌표 L, curve나 좌표변경 없음."""
    matches = list(TOKEN.finditer(value))
    last = 0
    for match in matches:
        require(not value[last:match.start()].strip(' \t\r\n,'), 'SVG token gap')
        last = match.end()
    require(not value[last:].strip(' \t\r\n,'), 'SVG trailing token')
    tokens = [match.group() for match in matches]
    point = start = (0.0, 0.0)
    index, command, result = 0, None, []
    while index < len(tokens):
        if tokens[index].isalpha():
            command = tokens[index]
            index += 1
        require(command in ('M', 'L', 'H', 'V', 'C', 'Z'), '지원하지 않는 SVG 명령')
        if command == 'Z':
            result.append({'kind': 'Z', 'points': []})
            point, command = start, None
            continue
        count = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6}[command]
        values = list(map(float, tokens[index:index + count]))
        require(len(values) == count, '잘린 SVG 명령')
        index += count
        if command == 'M':
            point = start = tuple(values)
            result.append({'kind': 'M', 'points': [point]})
            command = 'L'
        elif command in ('L', 'H', 'V'):
            point = ((values[0], point[1]) if command == 'H' else
                     (point[0], values[0]) if command == 'V' else tuple(values))
            result.append({'kind': 'L', 'points': [point]})
        else:
            points = [values[:2], values[2:4], values[4:]]
            result.append({'kind': 'C', 'points': points})
            point = tuple(points[-1])
    return result


def input_from_repository(repo):
    symbols, provenance = [], {}
    for name, (size, origin, expected) in SOURCES.items():
        relative = ('Researchers/Resources/Assets.xcassets/Entry' + name.title()
                    + '.imageset/' + name + '.svg')
        data = (repo / relative).read_bytes()
        require(sha(data) == expected, f'원본 SHA 불일치: {relative}')
        svg = ET.fromstring(data)
        paths = svg.findall('{http://www.w3.org/2000/svg}path')
        require(len(paths) == 1, 'SVG path는1개여야 합니다')
        d = paths[0].attrib['d']
        symbols.append({'name': name, 'size': size, 'origin': origin,
                        'commands': parse_path(d)})
        provenance[name] = {'path': relative, 'SHA256': expected,
                            'pathDSHA256': sha(d.encode()), 'viewBox': svg.attrib['viewBox']}
    return {'selectedIndices': SELECTED, 'symbols': symbols}, provenance


def simulator(udid):
    devices = json.loads(run(['xcrun', 'simctl', 'list', 'devices', 'available', '--json']))
    for runtime, items in devices['devices'].items():
        for device in items:
            if device['udid'].upper() == str(uuid.UUID(udid)).upper():
                require(device['state'] == 'Booted', '지정 Simulator가 이미 Booted여야 합니다')
                match = re.search(r'\.iOS-(\d+)-(\d+)', runtime)
                require(match, 'iOS Simulator만 지원합니다')
                return runtime, '.'.join(match.groups())
    raise ValueError('지정한 사용 가능한 Simulator가 없습니다')


def verify_and_manifest(repo, work, provenance, input_sha):
    require(sha((work / 'input.json').read_bytes()) == input_sha, '임시 입력 SHA 변경')
    _, after = input_from_repository(repo)
    require(after == provenance, '생성 중 원본 SVG 변경')
    decode = runpy.run_path(str(repo / 'scripts/verification/compare-entry-png.py'))['decode_png']
    export = json.loads((work / 'export-result.json').read_text())
    require(export['containsCalls'] == 1465856 and len(export['records']) == 9,
            '예상하지 못한 export 범위')
    records = []
    for item in export['records']:
        png = (work / item['file']).read_bytes()
        decoded = decode(png, item['file'])
        alpha = (work / item['a8File']).read_bytes()
        rgba = (work / item['runtimeRGBAFile']).read_bytes()
        require(decoded['metadata']['dimensions'] == item['dimensionsPX'], 'PNG 크기 불일치')
        require(decoded['alpha'] == alpha, 'PNG alpha와 계산 A8 불일치')
        require(rgba == bytes(c for a in alpha for c in (a, a, a, a)), 'runtime RGBA 불일치')
        rgb = decoded['rgb']
        rebuilt = bytes(c for i, a in enumerate(alpha)
                        for c in tuple((rgb[i * 3 + j] * a + 127) // 255 for j in range(3)) + (a,))
        require(rebuilt == rgba, 'PNG premultiply 결과 불일치')
        key = item['name'] + '@' + str(item['scale']) + 'x'
        require(sha(alpha) == EXPECTED[key]['alphaSHA256'], '기준 pixel alpha 불일치: ' + key)
        records.append({'name': item['name'], 'scale': item['scale'], 'file': item['file'],
                        'dimensionsPX': item['dimensionsPX'], 'PNGBytes': len(png),
                        'PNGSHA256': sha(png), 'alphaSHA256': sha(alpha),
                        'samePNGBytesAsBaseline': sha(png) == EXPECTED[key]['PNGSHA256'],
                        'alphaHistogram': dict(sorted(Counter(alpha).items())),
                        'alphaMismatchPixels': 0, 'runtimeRGBAMismatchBytes': 0})
    catalog = work / 'GeneratedAssets.xcassets'
    (catalog / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))
    for name in SOURCES:
        folder = catalog / ('Entry' + name.title() + 'Sampled.imageset')
        contents = {'images': [{'filename': f'{name}@{scale}x.png', 'idiom': 'universal',
                               'scale': f'{scale}x'} for scale in (1, 2, 3)],
                    'info': {'author': 'xcode', 'version': 1},
                    'properties': {'template-rendering-intent': 'template'}}
        (folder / 'Contents.json').write_text(json.dumps(contents, indent=2) + '\n')
    return {'sources': provenance, 'inputSHA256': input_sha, 'records': records,
            'exportContainsCalls': export['containsCalls'],
            'exportElapsedSeconds': export['elapsedSeconds'], 'alphaAllExact': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, default=Path.cwd())
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--simulator-udid', required=True)
    args = parser.parse_args()
    repo, output = args.repository.expanduser().resolve(), args.output.expanduser().resolve()
    require(output != repo and repo not in output.parents and output not in repo.parents,
            '출력은 저장소 바깥의 별도 폴더여야 합니다')
    require(not output.exists() or not any(output.iterdir()), '출력 폴더는 새 폴더/빈 폴더여야 합니다')
    configuration, provenance = input_from_repository(repo)
    runtime, deployment = simulator(args.simulator_udid)
    sdk = run(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'])
    sdk_version = run(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'])
    helper = Path(__file__).with_name('export-entry-symbols.swift')
    arch = platform.machine()
    require(arch in ('arm64', 'x86_64'), '지원하지 않는 Simulator architecture')
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.entry-symbol-work-', dir=output) as temporary:
        work = Path(temporary)
        (work / 'RawEvidence').mkdir()
        (work / 'input.json').write_text(json.dumps(configuration, indent=2) + '\n')
        input_sha = sha((work / 'input.json').read_bytes())
        binary = work / 'export-entry-symbols'
        run(['xcrun', 'swiftc', '-O', '-sdk', sdk, '-target',
             f'{arch}-apple-ios{deployment}-simulator', str(helper), '-o', str(binary)], timeout=60)
        run(['xcrun', 'simctl', 'spawn', args.simulator_udid, str(binary), str(work)], timeout=45)
        manifest = verify_and_manifest(repo, work, provenance, input_sha)
        manifest.update(simulatorUDID=args.simulator_udid, simulatorRuntime=runtime,
                        SDKVersion=sdk_version, architecture=arch,
                        exporterSwiftSHA256=sha(helper.read_bytes()),
                        exporterPythonSHA256=sha(Path(__file__).read_bytes()))
        shutil.move(str(work / 'GeneratedAssets.xcassets'), output / 'GeneratedAssets.xcassets')
        (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(output / 'manifest.json')


if __name__ == '__main__':
    main()
