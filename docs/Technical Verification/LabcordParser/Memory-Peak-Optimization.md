# 배치 최대 메모리 원인 분석·개선 재검증

2026-10-21. iPhone 17 / iOS 27.0.1(24A446), Release. **전후 각 6회 반복 측정·최종 회귀 검증 완료**.
이 문서의 원본은 최초 구현이 아니라 [직전 실기기 검증](Device-Batch-Korean-Verification.md)의
공유 PDF 작업창·팔레트 PNG·OCR 재사용을 적용한 44개 Swift 파일 버전이다.
최초 42개 파일 버전과 이번 기준 버전을 섞어 개선율을 계산하지 않는다.

## 관찰과 판단

- 원본 영문 배치의 예비 측정에서 관측 최대는 API 93.300초 중 91.237초에 발생했다.
  이때 마지막 200~204쪽의 페이지 OCR이 겹쳤다. 결과 조립은 93.239초부터 0.032초였으므로
  이 표본의 고점은 결과 조립이 아니다. 이 예비 실행은 별도 진단 실행이며 최종 비교 표본에서 제외한다.
- 실기기 VM 전용 Allocations 기록에서 Neural Engine 모델 로드 경로의 지속 할당 7개·156.44MiB,
  소유한 CG 래스터 4개·32.42MiB, IOSurface 33개·22.17MiB를 관찰했다.
  래스터의 스택은 `DocumentPDFPageSpace.render → CGBitmapContextCreateImage → create_protected_copy`다.
  Neural Engine은 `ANEDeviceOpen → _ANEProgramForEvaluation → _ANEClient doLoadModel` 경로였다.
- VM Tracker의 한 시점에는 Malloc Small dirty 439.98MiB와 Malloc Large 69.73MiB도 관찰됐다.
  이는 특정 스냅샷이며 위 할당 통계와 같은 시점의 전체 footprint 분해가 아니다. 단순 합산하지 않는다.
  이 자료만으로 retain cycle이나 메모리 누수를 확정하지 않는다.
- 기존 배치 작업당 Vision 예약은 32MiB였다. 이 값은 RGBA 작업량 외의 여유이며,
  여러 문서의 모델·중간 버퍼가 겹칠 때 전체 프로세스 고점을 충분히 나타내지 못한다.
  활성 작업 예약 상한과 프로세스 footprint는 다른 값이다.

## 시도한 대안

| 진단·예비 후보 | 실제 관찰 | 판단 |
| --- | --- | --- |
| OCR 호출 단위 autoreleasepool | 영문 API 97.202초, 최대 588.99MiB, 결과 지문 일치 | 원본 최대 595.03MiB와 차이가 약 1%로 작아 단독 해결로 판단하지 않음 |
| 배치 내 Vision 세션 재사용 | 영문 API 91.980초, 최대 585.32MiB, 결과 지문 일치 | 시간 여유를 확인했으나 고점 차이 약 1.6%만으로 메모리 개선을 확정하지 않음 |
| 할당기 메모리 반환 진단 | `malloc_zone_pressure_relief(nil, 0)` 반환 0바이트, 전후 footprint 517.66MiB 동일 | 앱 코드에 이 API를 적용하지 않음 |

위 예비 후보는 각각 1회이며, 영문 배치만 새 프로세스에서 실행해 최종 묶음과 시작 캐시 조건도 다르다.
최종 개선율은 아래 동일 순서의 전후 3회 결과로만 계산한다.
할당기 진단은 정상 열 상태를 기다리지 않은 별도 실험으로 성능 비교에서 제외했다.

전체 malloc 이벤트를 기록한 첫 진단은 계측 오버헤드가 커 테스트를 중단했다.
140초 trace는 저장됐으나 해당 XCTest를 통과 표본으로 세지 않는다.
이후 VM 전용 기록으로 범위를 좁혀 진단 실행을 완료했다.

## 적용한 후보

1. OCR 호출 하나가 끝나면 Vision 임시 객체를 정리한다. OCR 옵션·해상도는 유지한다.
2. `parse`/`parseBatch` 호출 범위에만 Vision 세션 풀을 둔다. 세션마다 같은 설정의
   `VNRecognizeTextRequest`와 `VNSequenceRequestHandler`를 재사용한다. 상위 작업창의 실행 동시성은
   유지하고, 작업이 끝난 유휴 세션은 최대 2개만 보관한다. 전역 영구 캐시가 아니다.
3. 세션 상태는 각각의 Mutex 안에서만 접근한다. 풀 잠금은 대여·반환에만 사용하므로 서로 다른
   세션의 OCR을 직렬화하지 않는다. 실패·취소한 세션은 재사용하지 않는다.
4. 배치의 작업당 Vision 예약 여유를 32→48MiB로 보정한다. 단일 문서는 기존 32MiB다.
   기본 옵션의 문서 동시성·PDF 작업창·256MiB 작업 목표·픽셀·PNG 한도는 바꾸지 않는다.
   늘어난 예약에 따라 배치의 실제 활성 페이지 수가 줄 수 있으며, 시간 유지 여부는 실측한다.

[Apple의 VNSequenceRequestHandler 문서](https://developer.apple.com/documentation/vision/vnsequencerequesthandler).
Xcode 27.1 SDK `VNRequestHandler.h`의 이미지 소유 수명 설명도 확인했다.
이미지 간 상태를 사용하는 추적 요청을 추가한 것이 아니며, 텍스트 요청 설정은 기존과 같다.
새 요청과 재사용 요청의 결과·방향·위치·신뢰도, 빈 이미지의 이전 결과 잔존 여부를 테스트한다.

UI·영구 저장·외부 업로드·의존성 추가는 없다. iOS 27.0·Swift 언어 모드 5.0과 저장소 서명 설정도 유지한다.

## 동일 조건의 실기기 비교

- 한국어 혼합: 국립국어연구원 125쪽 원본 + USGS 42쪽 + DOCX·HWP·JPEG·TXT·손상 PDF.
- 영문 혼합: USGS 204쪽 + USGS 42쪽 + 동일한 나머지 5개 입력.
- 문서 동시성 4, PDF 작업창 요청 6, 작업 목표 256MiB, PNG 500MiB, 이미지 개수 128.
- 각 묶음은 한국어→영문 순서이며, 묶음을 3회 반복한다. 묶음 사이에 프로세스를 다시 시작한다.
  영문은 앞선 한국어 실행의 프레임워크 캐시가 남을 수 있다. 전후 동일한 순서를 사용한다.
- 실행 전 nominal을 최대 360초 기다린다. API 시간에는 냉각 대기를 포함하지 않는다.
  시간은 3회 중앙값, 메모리는 20ms 간격 footprint의 3회 관측값 중 최대다.
  전체 OS 캐시 초기화·AB/BA 교차 순서·p95 검증을 수행한 것은 아니다.

| 시나리오 | 원본 API 중앙값, 초 | 원본 최대 footprint, MiB | 후보 API 중앙값 | 후보 최대 footprint |
| --- | ---: | ---: | --- | --- |
| 한국어 혼합 7개 | 114.381 | 423.85 | 113.723초 | 418.41MiB |
| 영문 혼합 7개 | 96.882 | 595.03 | 97.019초 | 572.71MiB |

전후 총 12회 모두 통과했고 nominal에서 시작했다. 텍스트·전체 블록·이미지 PNG·경고의
지문은 모든 반복에서 일치했다. 한국어 API는 0.57% 단축, 영문은 0.14% 증가해 거의 같았다.
최대 footprint는 각각 **1.28%·3.75% 감소**했다. 큰 폭의 메모리 해결로 해석하지 않는다.
배치 최대 활성 PDF 페이지는 5→4, 긴 PDF 내부는 4→3으로 줄었다. 추정 예약 목표는 지켰으며
반환 시 활성 페이지와 대기 요청은 모두 0이었다.

결과 보유 footprint 중앙값은 한국어 189.60→189.17MiB, 영문 292.56→296.60MiB다.
영문의 반환 후 메모리는 줄지 않았다. 시작 footprint 중앙값도 한국어 18.91→18.97MiB,
영문 68.92→71.17MiB로 차이가 있다. 3회 표본·고정 실행 순서이며 통계적 우월성이나
미측정 문서의 최대치, 전체 프로세스 256MiB 이하 동작을 보장하지 않는다.
최초 42개 파일 대비 과거 메모리 증가를 모두 해소했다고 주장하지 않는다.

프로토콜 전체는 원본 약 22.43분, 후보 약 18.61분이었다. 설치·열 상태 대기·재시작을
포함하므로 이 차이를 실제 API 처리량 개선으로 해석하지 않는다.

## 단계별 시간

긴 PDF 하나의 각 단계 누적 시간에 대해 3회 중앙값을 계산했다. 단위는 초다.
병렬 실행 시간과 대기가 서로 겹치므로 행을 더해 API 시간으로 해석하지 않는다.

| 단계 | 한국어 전→후 | 영문 전→후 |
| --- | ---: | ---: |
| 렌더링 | 2.463→2.419 | 42.169→41.918 |
| 이미지 추출·PNG | 2.777→2.749 | 4.709→4.792 |
| 이미지 OCR | 198.264→140.582 | 170.818→112.930 |
| 전체 페이지 OCR | 205.767→143.622 | 107.044→75.892 |
| 결과 조립 | 0.009→0.012 | 0.028→0.028 |
| 공용 예산 대기 | 42.064→42.703 | 18.529→18.488 |

원자료에는 전체 단계와 20ms footprint 곡선, 최대치 발생 시점, 입력별 지문을 보존했다.
[12회 원자료와 비교](Memory-Peak-Metrics.json).

## 진단 후 재확인

동일 VM 기록 설정의 수정 후 진단도 통과했다. 기록 종료 시점의 지속 할당은 Neural Engine
7개·156.44MiB로 같았고 CG 래스터는 4개·32.42→3개·23.86MiB,
IOSurface는 33개·22.17→32개·18.89MiB였다. 예약 보정으로 래스터 중첩이 줄었다는
관찰과 일치하지만 두 스냅샷의 작업 진행 시점은 완전히 같지 않다. 이 값을 성능 표의
footprint 차이와 일대일로 대응시키거나 누수 해결 증거로 사용하지 않는다.
이 진단은 냉각 대기 없이 프로파일러를 붙였으므로 최종 12회 비교에 포함하지 않았다.

중복 판별 문자열 정규화에 autoreleasepool을 추가한 별도 후보는 영문 최대 602.38MiB로
더 높았다. 결과 지문은 같았지만 이 변경은 최종 코드에서 되돌렸다.

## 추출 결과 유지 기준

원본과 후보에 동일한 테스트 측정 코드를 사용한다. 전체 텍스트뿐 아니라 다음 필드를
순서대로 스트리밍 SHA-256에 넣어 비교한다. 원문·그림 바이트를 로그나 보고서에 기록하지 않는다.

- 블록 종류·텍스트·읽기 순서·모든 원본 위치와 CGRect 성분·OCR 신뢰도 비트·원래 OCR 문자열.
- 이미지 ID·위치·방향·설명·PNG 바이트 전체.
- 경고 코드·메시지·전체 위치.

이미지 개수만 같고 PNG나 위치가 바뀐 경우도 검출한다. 전체 페이지 OCR·본문/블록 일관성,
입력 순서·6개 성공과 손상 문서의 개별 실패·단조 진행 이벤트·임시 디렉터리 정리도 검사한다.
한국어 125쪽 전체와 삽입 이미지 125개, 두 PDF 합계 167개 보존·기준 문구 12개를 확인한다.
이는 전후 동일 결과 검증이며 125쪽 전체 문자 정답률을 측정한 것은 아니다.

## 원자료와 재현

- 최종 소스 명세: [45개 파일 해시](Benchmarks/Memory-Peak-After-Source-SHA256.json).
- 원본 소스 명세: [44개 파일 해시](Benchmarks/Memory-Peak-Before-Source-SHA256.json).
- 원본 번들: `/tmp/issue21-memory-peak-before-final.xcresult`.
- 후보 번들: `/tmp/issue21-memory-peak-after-final.xcresult`.
- 원본 VM 진단: `/tmp/issue21-memory-vm2-before.trace`, 24MiB.
- 전체 할당 진단: `/tmp/issue21-memory-before-allocations.trace`, 약 12GiB. 최종 성능 비교에서 제외.
- 할당기 진단: `/tmp/issue21-memory-heap-probe-before.xcresult`.

```sh
python3 "docs/Technical Verification/LabcordParser/Tools/prepare_before_benchmark.py" \
  --baseline memory-peak --output /tmp/ResearchersMemoryBefore-고유이름
xcodebuild test -project /tmp/ResearchersMemoryBefore-고유이름/Researchers.xcodeproj \
  -scheme Researchers -configuration Release -derivedDataPath /tmp/ResearchersMemoryBeforeDD-고유이름 \
  -destination 'platform=iOS,id=연결된_기기_UDID' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -test-iterations 3 -test-repetition-relaunch-enabled YES \
  -only-testing:ResearchersTests/DocumentReleaseBatchBenchmarkTests/testKoreanMixedBatch \
  -only-testing:ResearchersTests/DocumentReleaseBatchBenchmarkTests/testReleaseMixedBatch \
  -resultBundlePath /tmp/ResearchersMemoryBefore-고유이름.xcresult \
  DEVELOPMENT_TEAM=사용가능한_팀 CODE_SIGN_STYLE=Automatic ENABLE_TESTABILITY=YES
```

후보는 현재 프로젝트와 별도 DerivedData·xcresult 경로로 같은 명령을 실행한다.
실제로는 원본을 먼저 build-for-testing한 뒤 test-without-building으로 실행했다.
`--baseline initial`은 더 이전 42개 파일 버전이며 이번 직접 비교의 기준이 아니다.

## 최종 회귀·빌드·린트

- iPhone 17 Release 일반 회귀 **110개 통과·실패 0개**, XCTest 17.199초.
  반복 성능·대용량 시나리오는 별도 실행한 위 12회와 구분하며 일반 회귀에서 제외했다.
- CI 명령의 시뮬레이터 앱 빌드 성공. `swiftlint lint --strict`: 100개 파일·위반 0개.
- 외부 원본 60개·20형식·6,029,910바이트와 추가 대용량 원본 3개 무결성 검증 통과.
- 최종 앱 소스 45개가 실제 반복 측정 버전의 SHA-256과 일치한다.
- 이번 메모리 보완 전후 프로젝트·공유 scheme·Package.resolved 해시가 일치한다.
  서명 팀은 실행 명령에만 지정했고 저장소 설정에 기록하지 않았다.

```sh
xcodebuild test -project Researchers.xcodeproj -scheme Researchers \
  -configuration Release -derivedDataPath /tmp/ResearchersMemoryAfterDD-고유이름 \
  -destination 'platform=iOS,id=연결된_기기_UDID' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -skip-testing:ResearchersTests/DocumentLargeScanTests \
  -skip-testing:ResearchersTests/DocumentKoreanScanTests \
  -skip-testing:ResearchersTests/DocumentReleaseBatchBenchmarkTests \
  -skip-testing:ResearchersTests/DocumentPerformanceTests/testHundredPagePDFReportsTimeAndSampledFootprint \
  -skip-testing:ResearchersTests/DocumentPDFParallelPerformanceTests/testCompareSerialAndParallelStageTimesOnHundredPages \
  -resultBundlePath /tmp/ResearchersMemoryRegression-고유이름.xcresult \
  DEVELOPMENT_TEAM=사용가능한_팀 CODE_SIGN_STYLE=Automatic ENABLE_TESTABILITY=YES
xcodebuild build -project Researchers.xcodeproj -scheme Researchers \
  -destination 'generic/platform=iOS Simulator'
swiftlint lint --strict
python3 "docs/Technical Verification/LabcordParser/Tools/verify_real_world_corpus.py"
```

로컬 증거: `/tmp/issue21-memory-peak-regression.xcresult`,
`/tmp/issue21-pr-ci-build.log`, `/tmp/issue21-pr-ci-lint.log`,
`/tmp/issue21-memory-vm-after.trace`. 원본 trace·xcresult·서명 자산은 저장소에 포함하지 않는다.
