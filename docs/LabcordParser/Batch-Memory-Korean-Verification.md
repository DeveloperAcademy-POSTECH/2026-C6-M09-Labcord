# 배치 작업 예산·PNG 메모리 개선과 한국어 스캔 검증

2026-10-21. 온디바이스 파싱만 변경했다. UI·영구 저장·의존성·iOS 27.0·Swift 언어 모드 5.0·저장소 서명 설정은 유지한다.

**후속 실기기 결과:** [iPhone 17 전후 반복 검증](Device-Batch-Korean-Verification.md).
재연결 후 한국어 단일·한국어 혼합·영문 혼합을 전후 각각 3회 검증했다.
아래 실기기 중단 기록과 시뮬레이터 수치는 당시 상태로 보존한다.

## 구현

- `parseBatch` 하나가 actor 기반 PDF 공용 작업 예산을 가진다. 기존의 문서별 고정 분할을 제거했다.
  준비·OCR의 진행 페이지 수는 배치 전체에서 요청 창·활성 CPU 수를 넘지 않는다.
- 슬롯을 반환하면 FIFO 대기 중인 PDF가 사용할 수 있다. 짧은 문서가 끝나도 긴 문서가 작은 창에
  고정되는 문제를 없앤다. 서로 다른 PDF의 PDFKit 객체를 공유하지 않는다.
- 추정 작업 메모리도 공용 예산에서 관리한다. 실제 래스터 크기를 알면 예약을 갱신한다.
  RGBA 작업량 외에 OCR 작업당 32MiB를 보수적으로 예약하여 작은 래스터의 Vision 작업도 제한한다.
  목표보다 큰 페이지는 혼자 처리한다. 이 설정은 PNG 결과·Vision 내부 캐시까지 포함한
  전체 프로세스 메모리의 강제 상한이 아니다. 독립적인 parse 호출 사이의 전역 풀도 아니다.
- 대기 중 취소는 continuation을 한 번만 재개하여 제거한다. 준비 실패·OCR 실패·취소 시
  예약을 반환한다. TaskGroup으로 자식 종료를 기다린다. 동기 Vision 내부의 즉시 취소는 보장하지 않는다.
- PNG는 불투명한 8비트 sRGB/DeviceRGB 이미지에 실제로 존재하는 색이 256개 이하인 경우에만 팔레트를
  사용한다. 양자화·리사이즈 없이 원본 RGB 값·색 공간을 유지한다. 다색·투명·다른 비트 깊이·
  인코딩 실패와 Display P3 등 광색역은 기존 인코더로 처리한다. OCR은 기존 CGImage에서 수행한다.
- 스캔 이미지 crop이 같은 페이지 래스터 전체와 영역·픽셀 크기가 정확히 같고 OCR이 성공했으면
  두 번째 동일 페이지 OCR은 재사용한다. pdfPageOCRReuse로 기록한다. 부분 그림·첫 인식 실패·
  그림 보존 한도 초과는 기존 전체 페이지 OCR을 수행한다. 인식 범위·해상도를 줄이지 않는다.
- maximumPDFImageBytes를 추가했다. 기본값은 기존 보존 범위와 같은 500MiB다.
  maximumExpandedBytes와 작은 값을 적용한다. 한도를 줄이면 보존 PNG가 적어질 수 있으므로
  이 경우의 메모리 절약을 같은 결과를 낸 성능 개선과 구분한다.
- metrics.batchScheduling에 전체 배치 최대 진행 페이지·추정 작업 바이트와 종료 시 예약·대기 수를,
  pdfSchedule 단계에 공용 창 대기 시간을 기록한다. 본문은 기록하지 않는다.

## 한국어 원본과 판정

[원본 명세](../../ResearchersTests/Fixtures/RealWorld/LargeScans/Manifest.json)의
`korean-1992.pdf`: 국립국어연구원, 1992, 「가나다 전화 자료집」.
**125쪽·3,857,838바이트**의 공식 원본 전체를 변경 없이 사용했다.
[개별 자료 페이지](https://www.korean.go.kr/front/reportData/reportDataView.do?mn_id=207&report_seq=94)에
공공누리 제1유형 출처표시가 명시되어 있다. 기관명·제목·연도·원문 링크를 유지한다.
학습용 AI 유형을 적용하거나 모델을 학습·업로드한 것이 아니다.

PDFKit으로 125쪽 모두 텍스트 층이 없고, 각 페이지에 스캔 이미지 리소스 하나가 있음을 확인했다.
4·11·60·125쪽을 직접 읽어 기준 문구 12개를 선택했다. 전체 페이지 OCR·원본/결과 페이지 수,
그림 보존 수·읽기 순서·전체 텍스트와 블록의 일관성·경고·기준 문구를 검사한다.
이미지 속 표는 OCR 텍스트만 대상이며 셀 구조 복원이나 125쪽 전체 문자 정확도를 주장하지 않는다.

한국어 혼합 배치는 이 125쪽 원본, USGS 42쪽 원본, DOCX·HWP·JPEG·고유 TXT·손상 PDF로
7개 입력이다. 문서 동시성 4·PDF 작업창 6·작업 메모리 목표 256MiB·PNG 한도 500MiB를
개선 전후 동일하게 적용한다. 시간·메모리를 비교할 때 그림을 더 적게 추출한 실행을 섞지 않는다.

## 실기기 상태

개선 전 기존 영문 7개 혼합 배치를 iPhone 17 / iOS 27.0.1 / Release에서 실행했다.
XCTest 재실행마다 프로세스를 다시 띄웠다. OS·파일·Vision의 모든 캐시가 비워진 cold 실행은 아니다.

| 개선 전 표본 | API 초 | 프로세스 footprint 표본 최대 MiB | 열 상태 |
| --- | ---: | ---: | --- |
| 1 | 168.583 | 522.81 | nominal→nominal |
| 2 | 180.635 | 510.52 | nominal→fair |

`/tmp/issue21-release-before.xcresult`에는 위 2개 성공 attachment가 있다. 3회차는 실기기 연결이
끊겨 테스트 러너 통신 오류로 실패했다. 파서 실패나 성공 표본으로 처리하지 않으며 연결 중단의 원인을 확정하지 않았다.
사용자가 당시 재연결할 수 없다고 알려 주어 그 시점에는 실기기 실행을 멈췄다.

**당시 미완료:** 개선 전 3회차, 개선 후 실기기 3회, 한국어 원본의 실기기 전후 비교.
후속 실기기 실행은 위 별도 보고서에 기록한다.
시뮬레이터 수치를 실기기 개선율로 바꾸어 보고하지 않는다.

## 재현과 후속 실기기 명령

개선 전 파서 42개 파일의 SHA-256을 [기준 소스 명세](Benchmarks/Before-Source-SHA256.json)에,
현재 버전에서 기준 버전으로 돌아가는 패치를 [기준 패치](Benchmarks/restore-before.patch)에 보관했다.
아래 스크립트는 저장소 밖의 **새 경로에만** 프로젝트를 복사하며 현재 작업 트리를 수정하거나
기존 경로를 덮어쓰지 않는다. 기준 파서 전체 파일 집합·해시를 검사한 뒤 신규 API 전용 테스트만
사본에서 제외한다. 테스트 샘플과 벤치마크 본문은 동일하다.

```sh
python3 scripts/DocumentParsing/verify_real_world_corpus.py
python3 scripts/DocumentParsing/prepare_before_benchmark.py --output /tmp/ResearchersParserBefore-새이름
xcodebuild test -project /tmp/ResearchersParserBefore-새이름/Researchers.xcodeproj \
  -scheme Researchers -configuration Release \
  -destination 'platform=iOS,id=연결된_기기_UDID' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -test-iterations 3 -test-repetition-relaunch-enabled YES \
  -only-testing:ResearchersTests/DocumentReleaseBatchBenchmarkTests/testReleaseMixedBatch \
  -only-testing:ResearchersTests/DocumentReleaseBatchBenchmarkTests/testKoreanMixedBatch \
  -only-testing:ResearchersTests/DocumentKoreanScanTests \
  -resultBundlePath /tmp/ResearchersBefore-고유이름.xcresult \
  DEVELOPMENT_TEAM=로컬_사용가능한_팀 CODE_SIGN_STYLE=Automatic ENABLE_TESTABILITY=YES
```

개선 후에는 같은 명령의 project를 현재 `Researchers.xcodeproj`로, 결과 경로를 새 이름으로 바꾼다.
128MiB 구성은 `testKoreanMixedBatchConservativeMemory`만 따로 골라 별도 결과 번들에서 3회 실행한다.
집계 스크립트는 같은 label의 같은 시나리오에 서로 다른 작업 예산이 섞이면 거부한다.
Release의 @testable import를 위해 ENABLE_TESTABILITY만 명령행으로 적용한다. 개발 팀·프로필·
배포 설정을 저장소에 반영하지 않는다. 실행 전 nominal을 최대 360초 기다리고 시작/종료 열 상태를
기록한다. nominal에 도달하지 못한 실행을 냉각이 통제된 성능 표본으로 간주하지 않는다.

CI 빌드·lint 및 개별 회귀 명령은 실행 결과 절에 기록한다.

## 시뮬레이터·빌드 결과

[수치와 페이지별 단계 JSON](Batch-Memory-Korean-Metrics.json).

### 동일 한국어 혼합 배치의 전후 관찰값

Release iOS Simulator / iPhone 17 시뮬레이터 / Mac 호스트. 각 행 **1회**이며 실기기 수치가 아니다.
작업 메모리 예산 외의 입력·문서 동시성 4·PDF 작업창 요청 6·PNG 한도는 동일하다.

| 버전·작업 메모리 목표 | API 초 | 시작 footprint MiB | 표본 최대 MiB | 결과 보유 footprint MiB | PDF PNG 합계 MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| 개선 전·256MiB | 651.568 | 19.44 | 344.00 | 226.11 | 66.94 |
| 개선 후·256MiB | 540.553 | 112.17 | 349.75 | 200.67 | 38.43 |
| 개선 후·128MiB | 491.513 | 19.64 | 340.97 | 198.58 | 38.43 |

- 128MiB 구성은 개선 전 대비 관찰 시간이 **24.6% 짧고**, 반환 결과를 보유한 시점의 프로세스
  footprint는 **12.2% 작았다**. 최대 footprint 차이는 **0.9%**뿐으로 최고값의 뚜렷한 감소를
  확인했다고 주장하지 않는다. 20ms 표본의 순간 최대 근사이며 전체 XCTest 프로세스·캐시를 포함한다.
- 개선 후 256MiB 행은 집중 테스트 11개 후에 같은 프로세스에서 실행되어 시작값이 더 높다.
  시간 단축 17.0%, 최대값 1.7% 증가라는 관찰값을 보관하지만, 새 프로세스의 전후 비교와 같은
  조건으로 해석하지 않는다. 128MiB 행은 벤치마크만 새 프로세스에서 실행했다.
- 두 개선 후 구성 모두 **7개 입력의 형식·성공/실패·텍스트 SHA-256·문자/블록/그림 수·수집한
  경고 코드/페이지 목록**이 개선 전과 일치했다. 전체 블록의 모든 좌표·신뢰도를 비교한 것은 아니다.
  진행률은 문서별 단조 증가했고 마지막 이벤트·반환 인덱스·개별 malformedDocument 실패 보존을 확인했다.
- 한국어 원본은 **125쪽·179,534자·4,946블록·그림 125개**, 경고 없음이며 기준 문구 12개가 통과했다.
  원본에는 텍스트 층이 없으므로 이 텍스트는 OCR에서 얻었다. 모든 페이지의 OCR 단계가 존재했다.
- PDF 그림은 **125+42=167개 그대로 보존**했다. 한국어 PNG는 48.04→25.29MiB, 두 PDF 합계는
  66.94→38.43MiB로 **42.6% 감소**했다. 해상도·그림 수·PNG 한도를 줄여 만든 차이가 아니다.
- 한국어 PDF의 그림 영역은 전체 페이지와 정확히 같은 영역이 아니므로 125쪽 모두 기존
  그림 OCR·전체 페이지 OCR을 수행했다. USGS 42쪽은 정확히 같은 전체 페이지 그림의 성공한 OCR을
  42회 재사용했다. 일반 부분 그림을 재사용 대상으로 넓히지 않았다.
- 공용 예산의 최대 예약 페이지는 256MiB 구성에서 **5**, 128MiB 구성에서 **2**였다.
  추정 예약 작업량은 각각 **255.06MiB / 109.94MiB**이고 종료 시 예약·대기 요청은 모두 0이다.
  이는 실제 프로세스 최대 메모리와 다른 지표다. 128MiB 구성에서 동시에 준비하는 래스터가 줄어도
  전체 시간은 더 짧았다. 이 표본으로 모든 기기·문서의 최적 병렬도를 확정하지 않는다.
- 모든 비교 행의 시작/종료 thermalState는 nominal이었다. 시뮬레이터의 ProcessInfo 값이며
  iPhone의 실제 열 상태·ANE 성능을 의미하지 않는다. OS/Vision 캐시를 비운 cold 실험이나 p95가 아니다.

### 한국어 PDF의 단계 합계

단위 초. 자식 OCR 구간·공용 창 대기는 겹치므로 합산하여 전체 경과 시간으로 쓰지 않는다.

| 단계 | 개선 전·256MiB | 개선 후·128MiB |
| --- | ---: | ---: |
| 페이지 렌더링 | 3.837 | 3.556 |
| 그림 crop·PNG | 3.418 | 3.719 |
| 그림 OCR 합계 | 319.424 | 347.969 |
| 전체 페이지 OCR 합계 | 324.709 | 399.715 |
| 공용 작업창 대기 합계 | 해당 없음 | 217.311 |
| 부모의 완료 대기 합계 | 644.215 | 266.698 |
| PDF 자체 경과 시간 | 651.552 | 491.485 |

### 실행 결과·초기 실패와 보완

- 개선 전 한국어 혼합 배치: **1개 통과**, XCTest 652.347초.
  `/tmp/issue21-korean-batch-before-simulator.xcresult`.
- 개선 후 256MiB 혼합 배치와 집중 테스트: **12개 통과**, 572.554초.
  `/tmp/issue21-korean-batch-after-final-simulator.xcresult`.
- 개선 후 128MiB 혼합 배치: **1개 통과**, 492.091초.
  `/tmp/issue21-korean-batch-memory128-simulator.xcresult`.
- 최종 Debug 시뮬레이터 회귀: **103개 통과**, 172.885초.
  `/tmp/issue21-pool-final-regression.xcresult`. 대용량 클래스·한국어 단일 클래스·배치 벤치마크
  클래스 전체와 기존 100쪽 성능 테스트 2개를 제외했다. 위 대용량 Release 검증과 구분한다.
- CI의 `xcodebuild build -project Researchers.xcodeproj -scheme Researchers
  -destination 'generic/platform=iOS Simulator'`: **성공**.
  `/tmp/issue21-pool-final-ci-build.log`.
- `swiftlint lint --strict`: **94개 파일, 0 violations**.
- 기존 60개 자산과 스캔 원본 3개의 해시·출처 검증 통과. 개선 전 사본 재현 스크립트는
  기준 소스 42개 파일 집합·해시 일치와 기존/저장소 내부 경로 덮어쓰기 거부도 확인했다.
- 프로젝트·공유 scheme·Package.resolved의 작업 전/후 SHA-256이 동일했다. 커밋·푸시는 하지 않았다.

초기 단일 한국어 실행은 125쪽 추출·문구·그림 검사에는 성공했지만 테스트가 Mac의 기본 작업 수
10을 6 이하로 잘못 가정해 실패했다. 명시적으로 작업 수를 6으로 고쳤고, 위 혼합 배치에서 동일한
125쪽 검사와 문구 기준을 재실행해 통과했다. 수정한 단일 메서드를 별도로 다시 실행했다고 주장하지 않는다.

Display P3 팔레트의 픽셀 비교에서는 반올림 차이를 발견했다. 해당 시도의 배치 측정을 중단하고
광색역을 기존 인코더로 처리하도록 제한한 뒤, P3 PNG 바이트·픽셀 일치 검사와 전체 집중 검증을
다시 통과했다. 중단·실패한 실행의 시간을 전후 비교에 사용하지 않았다.

재현할 때는 기준 버전에서 `testKoreanMixedBatch`, 개선 버전에서 같은 메서드 또는
`testKoreanMixedBatchConservativeMemory`만 골라 새 프로세스로 실행한다. 혼합 배치에
한국어 125쪽 원본이 전부 들어가며 일부 페이지만 뽑은 성능값이 아니다.

```sh
xcodebuild test -project Researchers.xcodeproj -scheme Researchers -configuration Release \
  -destination 'platform=iOS Simulator,id=시뮬레이터_UDID' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ResearchersTests/DocumentReleaseBatchBenchmarkTests/testKoreanMixedBatchConservativeMemory \
  -resultBundlePath /tmp/ResearchersMemory128-고유이름.xcresult ENABLE_TESTABILITY=YES
python3 scripts/DocumentParsing/summarize_benchmark.py \
  --run before-simulator=/tmp/기준버전.xcresult \
  --run after-conservative-simulator=/tmp/개선버전128.xcresult \
  --output /tmp/파싱비교.json
```

103개 회귀 실행 명령:

```sh
xcodebuild test -project Researchers.xcodeproj -scheme Researchers \
  -destination 'platform=iOS Simulator,id=시뮬레이터_UDID' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -skip-testing:ResearchersTests/DocumentLargeScanTests \
  -skip-testing:ResearchersTests/DocumentKoreanScanTests \
  -skip-testing:ResearchersTests/DocumentReleaseBatchBenchmarkTests \
  -skip-testing:ResearchersTests/DocumentPerformanceTests/testHundredPagePDFReportsTimeAndSampledFootprint \
  -skip-testing:ResearchersTests/DocumentPDFParallelPerformanceTests/testCompareSerialAndParallelStageTimesOnHundredPages \
  -resultBundlePath /tmp/ResearchersRegression-고유이름.xcresult
```

동시 빌드의 DB 충돌을 막기 위해 실제 시뮬레이터 실행에는 별도
`-derivedDataPath /tmp/issue21-large-ci-dd`를 사용했다. CI 빌드는 기본 경로로 정확한 명령을 실행했다.

## PNG/작업 예산 조정

기본 페이지 작업 목표 256MiB, 문서 동시성 2는 유지한다. PNG 500MiB 기본값도 유지하여
그림 누락으로 성능 개선을 만들지 않는다. 대용량 배치에서 모든 그림을 메모리로 반환하는 API이므로,
결과 보유량이 크면 문서 동시성을 1~2로 낮추거나 maximumPDFImageBytes를 별도로 제한할 수 있다.
32/64MiB 같은 낮은 한도는 원본에 따라 부분 경고와 그림 누락을 발생시키며 보편적인 안전 상한은 아니다.
당시에는 실기기 전후 측정이 완료되지 않아 더 낮은 기본값이나 최적값을 확정하지 않았다.
후속 실기기 256MiB 구성에서도 배치 최대 메모리가 증가했으므로, PNG 용량 감소를
전체 프로세스 최대 메모리 개선으로 설명하지 않는다. 세부 조건은 후속 보고서를 따른다.

현재 한국어 샘플의 문서별 PNG 합계는 25.29MiB/13.14MiB이므로 32MiB·64MiB 보존 예산 안에
들어간다. 이는 관찰된 PNG 크기를 기준으로 한 설정 판단이며, 그 한도로 별도 전체 파싱을 실행해
최대 프로세스 메모리를 비교한 결과는 아니다. 1바이트 PNG 한도 회귀에서는 그림 보존을 제한하고
위치 경고를 남겨도 전체 페이지 OCR이 유지되는 경로를 검증했다.

```swift
// 메모리 우선 구성을 선택할 때: 원본의 결과 보유량도 별도로 확인한다.
let options = DocumentParserOptions(
  pdfWorkingMemoryTargetBytes: 128 * 1024 * 1024,
  maximumPDFImageBytes: 64 * 1024 * 1024)
```

## 변경 파일

| 위치 | 변경 내용 |
| --- | --- |
| `Researchers/Services/DocumentParsing/Core/DocumentParser.swift` | 배치 공용 예산의 수명과 결과 지표 연결 |
| `Researchers/Services/DocumentParsing/Models/DocumentParsingModels.swift` | PDF PNG 보존 바이트 옵션 |
| `Researchers/Services/DocumentParsing/Models/DocumentParsingMetrics.swift` | 배치 예약 지표·예약 대기·OCR 재사용 단계 |
| `Researchers/Services/DocumentParsing/PDF/Pages/DocumentPDFWorkPool.swift` | FIFO·취소·반환을 관리하는 actor와 TaskLocal |
| `Researchers/Services/DocumentParsing/PDF/Pages/DocumentPDFPipeline.swift` | 공용 예약·실제 래스터 비용 갱신·보존 예산 |
| `Researchers/Services/DocumentParsing/PDF/Pages/DocumentPDFPreparedPage.swift` | 전체 페이지 일치 판정·OCR 예약 여유 |
| `Researchers/Services/DocumentParsing/PDF/Pages/DocumentPDFPageParser.swift` | 동일 전체 페이지 OCR 재사용 |
| `Researchers/Services/DocumentParsing/PDF/Extraction/Images/` | 무손실 팔레트 인코더와 기존 그림 추출 연결 |
| `ResearchersTests/DocumentParsing/PDF/` | 작업 예산·PNG·재사용·한국어·Release 벤치마크 및 기존 배치 검사 보강 |
| `ResearchersTests/Support/PDF/` | 한국어 원본/문구 검증과 배치 수치 수집 |
| `ResearchersTests/Fixtures/RealWorld/LargeScans/` | 한국어 원본·출처/권리/해시 명세 |
| `scripts/DocumentParsing/prepare_before_benchmark.py` | 작업 트리를 보존하는 기준 버전 재현 |
| `scripts/DocumentParsing/summarize_benchmark.py` | 수치 집계·동일 시나리오 전후 비교 |
| `docs/LabcordParser/` | API·측정값·기준 패치/해시·초기 실패와 미완료 항목 |
