# 실제 대용량 스캔 PDF·혼합 배치 검증

이 문서는 공용 배치 예산 도입 전의 기록이다. 최신 구현과 측정·미완료 항목은
[배치·메모리·한국어 검증](Batch-Memory-Korean-Verification.md)을 따른다.

2026-10-21. iPhone 17 / iOS 27.0.1 / Xcode 27.1 / Debug XCTest.

## 입력

| 원본 | 실제 PDF 페이지 | 바이트 | 성격 |
| --- | ---: | ---: | --- |
| USGS Professional Paper 158 (1930) | 204 | 31,644,622 | 2단 본문·도판·지도·목차·기존 OCR 층이 있는 스캔 |
| USGS Water Supply Paper 158 (1906) | 42 | 2,046,636 | 본문·표·지도·기존 OCR 층이 있는 스캔 |

- 위 두 파일은 공식 USGS 원본 전체를 변경 없이 보관한다. 출처·권리·SHA-256은
  [자산 명세](../../../ResearchersTests/Fixtures/RealWorld/LargeScans/Manifest.json)를 따른다.
- [USGS 권리 정책](https://www.usgs.gov/information-policies-and-instructions/copyrights-and-credits)에
  따른 미국 public domain 자료이며 출처를 표시했다. 제삼자 자료 일반에 확대 적용하지 않는다.
- 42쪽 원본 전체를 1224×1584 썸네일로 렌더링한 래스터 전용 파생본도 실행한다.
  PDFKit에서 모든 페이지의 텍스트가 비어 있는지 검증하여 OCR만으로 추출됨을 확인한다.
  이 파생본은 원본 파일이나 원본 스캔 해상도 성능과 구분한다.
- 혼합 배치는 서로 다른 두 원본 PDF, DOCX 표·각주 문서, HWP 문서, 대출 계산 JPEG,
  고유 마커 TXT, 손상 PDF의 **7개 입력**이다. 동일 PDF를 복제한 배치가 아니다.
- 외부 파일은 테스트 번들에만 포함한다. 앱·테스트 실행 중 네트워크 다운로드는 없다.

## 측정과 판정

- 원본 204쪽은 페이지 작업 수 1과 6으로 실행한다. 페이지 OCR 단계가 모두 수행됐는지,
  결과 블록·그림·경고가 순차/병렬에서 동일한지 확인한다.
- 배치는 문서 동시성 2와 4, 전체 PDF 작업창 요청 6으로 실행한다. 문서별 창은 각각
  3과 1로 나뉜다. 전체 PDF 작업창이 6까지 늘어났다는 의미가 아니다.
- 모든 입력의 마지막 이벤트, 진행률 단조 증가, 정상 결과 6건과 개별 실패 1건,
  입력 인덱스와 형식, 완료 전 입력이 겹치는 실제 동시 실행 수를 검사한다.
- OCR 수행 페이지 수, 텍스트가 있는 페이지 번호, 블록/그림/문자 수, 경고 코드·페이지,
  결과 텍스트 SHA-256, 단계별 구간을 JSON attachment로 기록한다. 본문은 기록하지 않는다.
- 프로세스 physical footprint를 20ms 간격으로 표본 수집한다. 이는 순간 최대치의 근사이고
  XCTest 호스트·프레임워크 캐시·보유 결과를 포함한다. 256MiB 설정은 PDF 작업 추정 목표이며
  프로세스 전체 메모리 상한이 아니다. 독립적인 여러 parse 호출에 전역 제한은 없다.
- 단일 원본 비교는 직전 순차 결과를 보유하여 완전 일치 비교한다. 이후 실행 메모리는
  보유 중인 결과를 포함하므로 단독 cold 실행의 메모리라고 해석하지 않는다.
- 페이지 3쪽/그림 1개 제한에서 부분 결과와 남은 페이지 위치 경고를 확인한다.
  실제 배치를 OCR 진행 후 취소하고 반환 지연 및 파서 임시 폴더의 실행 전/후 집합을 확인한다.

## 재현 명령

```sh
python3 "docs/Technical Verification/LabcordParser/Tools/verify_real_world_corpus.py"
xcodebuild test -project Researchers.xcodeproj -scheme Researchers \
  -destination 'platform=iOS,id=연결된_기기_UDID' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ResearchersTests/DocumentLargeScanTests \
  -resultBundlePath /tmp/ResearchersLargeScan-고유이름.xcresult \
  DEVELOPMENT_TEAM=로컬_사용가능한_팀 CODE_SIGN_STYLE=Automatic
xcodebuild build -project Researchers.xcodeproj -scheme Researchers \
  -destination 'generic/platform=iOS Simulator'
swiftlint lint --strict
```

개발 팀은 명령행에서만 적용한다. 저장소 서명 설정은 변경하지 않는다.
전체 204쪽을 여러 차례 OCR하므로 기존 소형 코퍼스 회귀 테스트보다 오래 걸린다.

## 결과

[전체 수치·페이지별 단계 구간 JSON](Large-Scan-Batch-Metrics.json).

| 처리 | API 경과 초 | 시작 footprint MiB | 표본 최대 MiB | 실제 최대 작업 |
| --- | ---: | ---: | ---: | --- |
| 원본 204쪽, 페이지 작업 1 | 161.987 | 304.94 | 493.13 | 페이지 1 |
| 원본 204쪽, 페이지 작업 6 | 136.969 | 309.10 | 564.50 | 페이지 6 |
| 혼합 7개, 문서 동시성 2 | 145.521 | 238.25 | 561.49 | 문서 2·각 PDF 페이지 3 |
| 혼합 7개, 문서 동시성 4 | 181.937 | 300.78 | 495.44 | 문서 4·각 PDF 페이지 1 |
| 래스터 전용 42쪽 파생본 | 27.277 | 548.92 | 669.55 | 페이지 6 |

- 204쪽 결과는 순차·병렬 모두 **29,948블록·1,216,649자·128개 그림**이며 블록·그림·경고가
  완전히 일치했다. 204개 페이지 OCR 단계가 실행됐다. 텍스트가 나온 페이지는 203개이며
  나머지 **141쪽은 원본 렌더링을 직접 확인한 빈 스캔 페이지**다.
- 기본 그림 한도 128개에 도달하여 129–204쪽에 위치가 있는 resourceLimitReached 경고
  76건을 남겼다. 보존한 PNG는 합계 **112,868,275바이트**로 입력 PDF보다 크다.
  그림 한도 이후에도 전체 페이지 OCR은 모두 수행했다. 읽기 순서 관련 경고는 259건이며,
  추출/OCR 실패·손상 경고는 없었다. 따라서 모든 그림을 무제한 보존했다고 해석하면 안 된다.
- 래스터 전용 파생본은 42쪽 모두 OCR 텍스트가 있으며 3,723개 OCR 블록·97,084자를
  얻었다. paragraph/tableCell 블록이 없고 경고도 없었다. 27.277초는 파싱 API 시간이며
  원본을 래스터 파생본으로 만드는 약 7.2초는 제외했다. 준비 직후 baseline이 이미
  548.92MiB이므로 669.55MiB를 파서만의 추가 사용량이라고 해석하지 않는다.
- 두 배치 모두 정상 6건·손상 PDF malformedDocument 1건을 원래 인덱스에 반환했다.
  완료 순서는 동시성 2에서 1→2→3→4→5→6→0, 동시성 4에서 2→4→5→6→3→1→0이었다.
  반환 배열은 각각 0→6으로 유지됐고, 모든 문서의 진행률은 단조 증가했다.
- 이 배치에서는 동시성 4가 2보다 느렸다. 고정 문서별 PDF 작업창 배분이 3→1로 줄고
  빈 문서 슬롯을 남은 PDF에 다시 배정하지 않는 현재 정책의 영향도 포함한다. 반면 뒤쪽
  TXT는 동시성 2에서 약 66.65초, 4에서 약 1.04초에 완료되어 짧은 문서 대기 시간은 줄었다.
  기본 문서 동시성 2를 유지한다. 이 두 실행만으로 모든 입력의 최적값을 정하지 않는다.
- 긴 배치가 진행 중임을 확인하기 위해 **동시성 4 구간에 Time Profiler를 5초 부착**했다.
  OCR 디코딩·PNG 인코딩의 활성 샘플을 확인했다. 이 행은 순수 벤치마크가 아닌 관찰값이다.
- 열 상태는 동시성 2에서 nominal→nominal, 4에서 nominal→fair, 단일 원본 두 실행에서
  fair→fair, 래스터 전용에서 fair→serious였다. 재시작·냉각·반복 순서 교차를 통제한 실험이
  아니므로 15.4%의 관찰된 순차 대비 단축을 일반적인 성능 보장으로 사용하지 않는다.
- 실제 배치 OCR 중 취소 요청부터 반환까지 **0.436초**였고 파서 임시 폴더가 추가되지 않았다.
  배치 전체 취소는 배열 반환 대신 예외를 던진다. 이미 완료된 개별 결과를 취소 시 별도로
  회수하는 API가 검증된 것은 아니다. 개별 문서 실패의 결과 보존과 구분한다.

### 단계별 시간

204쪽 원본의 각 단계 합계, 단위 초. 병렬 자식 구간은 겹치므로 합계를 전체 시간으로
더하지 않는다. 원본의 이미지 OCR 128건·페이지 OCR 204건 모두 측정에 포함된다.

| 단계 | 작업 1 | 작업 6 |
| --- | ---: | ---: |
| 열기 | 0.001 | 0.001 |
| 연산자·그림 배치 | 0.095 | 0.111 |
| 표 분석 | 4.141 | 4.896 |
| 기존 텍스트 층 추출 | 0.074 | 0.093 |
| 렌더링 | 35.774 | 45.127 |
| 그림 crop·PNG 준비 | 3.287 | 4.451 |
| 그림 OCR 합계 | 44.993 | 276.484 |
| 전체 페이지 OCR·중복 검사 합계 | 72.955 | 467.117 |
| 결과 조합 | 0.088 | 0.084 |
| 부모 완료 대기, 자식과 중첩 | 118.455 | 82.122 |

### 실행 결과와 아티팩트

- 실기기 대용량 4개 테스트: **모두 통과**, XCTest 662.940초.
  `/tmp/issue21-large-scan-device2.xcresult` / 같은 이름 `.log`.
- 원본 해시·페이지 수 신규 검사와 최신 입력 바이트 제한·취소 재검사,
  기존 PDF 병렬 회귀 4개: **6개 통과**, 5.767초.
  `/tmp/issue21-large-scan-final-device.xcresult`.
- 새 대용량 클래스는 총 5개 메서드이며 위 두 실행으로 모두 검증했다.
  한 번의 실행에서 5개를 함께 실행했다고 주장하지 않는다.
- 시뮬레이터 기존 회귀: **92개 통과**, 88.267초.
  `/tmp/issue21-large-regression-simulator.xcresult`. 대용량 클래스 전체와
  자체 생성 100쪽 성능 테스트 2개를 제외했다.
- CI 기준 generic iOS Simulator 빌드 **성공**. 동시 실기기 실행과 빌드 DB를 분리하려고
  `-derivedDataPath /tmp/issue21-large-ci-dd`만 추가했다.
  `/tmp/issue21-large-ci-build.log`.
- `swiftlint lint --strict`: **86개 파일, 0 violations**.
- 원래 코퍼스 **60개·6,029,910바이트**와 추가 원본 2개의 SHA-256·출처 검사 통과.
- 프로젝트·공유 scheme·Package.resolved의 작업 전/후 SHA-256이 일치했다.
  저장소 서명 설정·의존성·iOS/Swift 언어 모드·앱 파서 코드를 바꾸지 않았다.
- 테스트 코드·보조 측정 코드·원본 2개(합계 약 32.13MiB)·출처 명세·해시 검사·이 문서를
  추가/보강했다. 원본 파일을 앱 타깃에 포함하지 않았다. 커밋·푸시는 하지 않았다.

보충 실행 명령:

```sh
xcodebuild test -project Researchers.xcodeproj -scheme Researchers \
  -destination 'platform=iOS,id=연결된_기기_UDID' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ResearchersTests/DocumentLargeScanTests/testLargeScanOriginalHashesAndPageCounts \
  -only-testing:ResearchersTests/DocumentLargeScanTests/testLargeScanLimitsCancellationAndCleanup \
  -only-testing:ResearchersTests/DocumentPDFParallelTests \
  -resultBundlePath /tmp/ResearchersLargeScan-Final-고유이름.xcresult \
  DEVELOPMENT_TEAM=로컬_사용가능한_팀 CODE_SIGN_STYLE=Automatic
```

시뮬레이터 회귀 실행 명령:

```sh
xcodebuild test -project Researchers.xcodeproj -scheme Researchers \
  -destination 'platform=iOS Simulator,id=시뮬레이터_UDID' \
  -derivedDataPath /tmp/issue21-large-ci-dd \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -skip-testing:ResearchersTests/DocumentLargeScanTests \
  -skip-testing:ResearchersTests/DocumentPerformanceTests/testHundredPagePDFReportsTimeAndSampledFootprint \
  -skip-testing:ResearchersTests/DocumentPDFParallelPerformanceTests/testCompareSerialAndParallelStageTimesOnHundredPages \
  -resultBundlePath /tmp/ResearchersLargeScan-Regression-고유이름.xcresult
```

## 검증 범위의 한계

원본 텍스트 층은 이전 OCR의 결과로 오인식이 포함된다. 전체 페이지의 수작업 정답과
문자 정확도 비교를 완료한 것은 아니다. 스캔 이미지 속 표는 OCR 텍스트만 대상이며 셀
구조 복원은 보장하지 않는다. 위치·페이지·순서·부분 실패·일관성과 성능을 검증한다.
단일 기기·한 번씩의 실행으로 모든 대형 PDF, 최소 메모리 기기, Release 성능이나 p95를
보장하지 않는다. 암호화·손상·개체 구조가 다른 문서는 기존 회귀 테스트와 함께 판단한다.
