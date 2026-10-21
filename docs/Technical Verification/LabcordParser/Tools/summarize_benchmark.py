"""xcresult의 수치 attachment를 모아 같은 시나리오·환경의 전후 결과만 비교한다."""

import argparse
import collections
import json
import statistics
import subprocess
import tempfile
from pathlib import Path


def read_bundle(path):
    with tempfile.TemporaryDirectory(prefix='document-benchmark-') as directory:
        subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', path,
                        '--output-path', directory], capture_output=True, check=True)
        root = Path(directory)
        rows = []
        for test in json.loads((root / 'manifest.json').read_text()):
            for attachment in test['attachments']:
                name = attachment['suggestedHumanReadableName']
                single = name.startswith('korean-original-125-pages')
                if not single and not name.startswith('release-mixed-batch'):
                    continue
                row = json.loads((root / attachment['exportedFileName']).read_text())
                row['testIdentifier'] = test['testIdentifier']
                if single:
                    row['scenario'] = 'korean-single-125'
                    row['results'] = [row.pop('result')]
                row.setdefault('scenario', 'english-mixed-7')
                for result in row.get('results', []):
                    if 'textSHA256' in result:
                        result['textSHA256'] = result['textSHA256'].replace('SHA256 digest: ', '')
                    sums = collections.Counter()
                    for timing in result.get('timings', []):
                        sums[timing['stage']] += timing['seconds']
                    result['stageSumsSeconds'] = dict(sums)
                rows.append(row)
        summary = subprocess.run(
            ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', path,
             '--format', 'json'], capture_output=True, check=True, text=True)
        metadata = json.loads(summary.stdout)
        fields = ['title', 'result', 'passedTests', 'failedTests', 'skippedTests',
                  'totalTestCount', 'startTime', 'finishTime']
        safe_summary = {key: metadata[key] for key in fields if key in metadata}
        return {'bundlePath': path, 'bundleSummary': safe_summary, 'runs': rows}


def progress_checks(run):
    events = run['events']
    active = set()
    peak = 0
    for event in events:
        if event['phase'] == 'identifying':
            active.add(event['index'])
        peak = max(peak, len(active))
        if event['phase'] in {'completed', 'failed', 'cancelled'}:
            active.discard(event['index'])
    valid = not active
    for index, result in enumerate(run['results']):
        values = [event for event in events if event['index'] == index]
        fractions = [event['fraction'] for event in values]
        terminal = 'failed' if 'failure' in result else 'completed'
        valid = valid and bool(values) and values[-1]['phase'] == terminal
        valid = valid and fractions == sorted(fractions)
    return {'monotonicAndTerminalEventsValid': valid, 'peakActiveDocuments': peak}


def stage_medians(runs):
    results = []
    for index in range(len(runs[0]['results'])):
        stages = {stage for run in runs
                  for stage in run['results'][index].get('stageSumsSeconds', {})}
        results.append({stage: statistics.median(
            run['results'][index].get('stageSumsSeconds', {}).get(stage, 0) for run in runs)
                        for stage in sorted(stages)})
    return results


def compare(before, after):
    pairs = []
    for scenario in sorted({row['scenario'] for row in before}):
        first = [r for r in before if r['scenario'] == scenario]
        second = [r for r in after if r['scenario'] == scenario]
        environments = {r['environment'] for r in first + second}
        if not second or len(environments) != 1:
            continue
        if any(run.get('diagnosticProfile', False) for run in first + second):
            raise ValueError('계측·메모리 진단 실행은 성능 비교에 포함할 수 없습니다')
        for rows in [first, second]:
            budgets = {r.get('pdfWorkingMemoryTargetBytes', 256 * 2**20) for r in rows}
            if len(budgets) != 1:
                raise ValueError('한 label 안에 같은 시나리오의 서로 다른 예산이 있습니다')
        old = statistics.median(r['wallSeconds'] for r in first)
        new = statistics.median(r['wallSeconds'] for r in second)
        peak_old = max(r['sampledPeakFootprintBytes'] for r in first)
        peak_new = max(r['sampledPeakFootprintBytes'] for r in second)
        keys = ['format', 'failure', 'textSHA256', 'textCharacters', 'blocks', 'images', 'warnings',
                'blocksSHA256', 'imagesSHA256', 'warningsSHA256']
        def summaries(run):
            return [{k: d.get(k) for k in keys} for d in run['results']]
        results_old = summaries(first[0])
        results_new = summaries(second[0])
        pairs.append({
            'scenario': scenario, 'environment': next(iter(environments)),
            'samplesBefore': len(first), 'samplesAfter': len(second),
            'beforeWorkingMemoryTargetMiB': first[0].get(
                'pdfWorkingMemoryTargetBytes', 256 * 2**20) / 2**20,
            'afterWorkingMemoryTargetMiB': second[0].get(
                'pdfWorkingMemoryTargetBytes', 256 * 2**20) / 2**20,
            'beforeMedianSeconds': old, 'afterMedianSeconds': new,
            'timeReductionPercent': (old - new) / old * 100,
            'peakBeforeMiB': peak_old / 2**20, 'peakAfterMiB': peak_new / 2**20,
            'peakReductionPercent': (peak_old - peak_new) / peak_old * 100,
            'beforeMedianBaselineMiB': statistics.median(
                r['baselineFootprintBytes'] for r in first) / 2**20,
            'afterMedianBaselineMiB': statistics.median(
                r['baselineFootprintBytes'] for r in second) / 2**20,
            'beforeMedianResultHeldMiB': statistics.median(
                r['afterFootprintBytes'] for r in first) / 2**20,
            'afterMedianResultHeldMiB': statistics.median(
                r['afterFootprintBytes'] for r in second) / 2**20,
            'beforeStageMediansSeconds': stage_medians(first),
            'afterStageMediansSeconds': stage_medians(second),
            'sameCollectedResultSummaries': results_old == results_new,
            'allRunsMatchBeforeSummary': all(
                summaries(run) == results_old for run in first + second),
            'fullResultFingerprintsCompared': all(
                all(key in result for key in ['blocksSHA256', 'imagesSHA256', 'warningsSHA256'])
                for run in first + second for result in run['results'] if 'failure' not in result),
            'allRunsStartedNominal': all(run['thermalBefore'] == 0 for run in first + second),
            'perInputSummaryMatches': [a == b for a, b in zip(results_old, results_new)],
            'progressBefore': progress_checks(first[0]),
            'progressAfter': progress_checks(second[0]),
            'progressAllRuns': [progress_checks(run) for run in first + second],
        })
    return pairs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', action='append', required=True, help='label=xcresult_path')
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    groups = {}
    for value in args.run:
        label, path = value.split('=', 1)
        if label in groups:
            raise ValueError(f'중복 label: {label}')
        groups[label] = read_bundle(path)
    comparisons = []
    for label, group in groups.items():
        environment = next((suffix for suffix in ['simulator', 'device']
                            if label.endswith(suffix)), None)
        if label.startswith('after-') and environment:
            for comparison in compare(groups.get(f'before-{environment}', {}).get('runs', []),
                                      group['runs']):
                comparison['afterLabel'] = label
                comparisons.append(comparison)
    Path(args.output).write_text(json.dumps(
        {'groups': groups, 'comparisons': comparisons}, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(comparisons, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
