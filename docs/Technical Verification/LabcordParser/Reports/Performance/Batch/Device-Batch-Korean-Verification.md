# iPhone 17 한국어 대용량 스캔·혼합 배치 전후 검증

2026-10-21. iPhone 17(iPhone18,3), iOS 27.0.1(24A446), Release.
실제 연결된 기기에서 실행했다. 시뮬레이터 결과는 아래 표에 섞지 않는다.
개발 팀·서명은 xcodebuild 명령행에만 적용했다. iOS 27.0·Swift 언어 모드 5.0,
의존성과 앱 코드는 이번 검증에서 변경하지 않았다.

## 측정 조건

- [기준 소스 명세](../../../Benchmarks/Before-Source-SHA256.json)의 개선 전 Swift 파일 42개를
  `prepare_before_benchmark.py`로 별도 프로젝트에 복원하고 전체 파일 집합·해시를 확인했다.
  현재 작업 트리의 파서를 교체하지 않았다. 개선 전후 테스트 본문·원본 샘플은 동일하다.
- 세 시나리오를 같은 순서로 한 묶음에 실행하고, 이 묶음을 3회 반복했다.
  `-test-repetition-relaunch-enabled YES`로 묶음 사이에 테스트 프로세스를 다시 시작했다.
  한 묶음 안의 단일 한국어→한국어 혼합→영문 혼합 사이에는 Vision 캐시가 남을 수 있다.
  OS·파일·Vision 캐시 전체를 비운 cold 측정은 아니다.
- 혼합 배치는 문서 동시성 4, PDF 작업창 요청 6, 작업 메모리 목표 256MiB,
  문서당 PNG 보존 한도 500MiB, 그림 개수 한도 128로 전후 동일하다.
  한국어 단일은 작업창 요청 6과 나머지 기본 설정을 사용한다.
- 각 실행은 nominal 열 상태를 최대 360초 기다린다. 대기 시간은 API 측정에서 제외한다.
  본 비교의 전후 18회는 모두 nominal에서 시작했다. 일부 실행은 fair에서 끝났다.
- 시간은 API wall time의 3회 중앙값, 최대 메모리는 20ms 간격 Mach physical footprint의
  **3회 관측값 중 최대**다. 결과 보유 메모리는 반환 결과가 살아 있는 시점의 프로세스 값이다.
  앱 전체·Vision·PDFKit·캐시를 포함하며, 해제 후 메모리나 누수 검사 수치가 아니다.
- 개선 전 묶음 3회 뒤 개선 후 묶음 3회를 실행했다. AB/BA 교차 실행이 아니며,
  장시간 실행·기기 사용·주변 온도·OS 캐시의 영향을 완전히 통제하지 않았다. 표본 3개로 p95를 주장하지 않는다.

## 원본과 검사 범위

[원본 명세·라이선스](../../../../../../ResearchersTests/Fixtures/RealWorld/LargeScans/Manifest.json).
외부 다운로드나 업로드 없이 이미 보관된 공식 원본 전체를 기기에서 처리했다.

- 한국어 단일: 국립국어연구원 1992 「가나다 전화 자료집」 125쪽, 텍스트 층 없음,
  공공누리 제1유형 출처표시. 125쪽·125개 그림·전체 페이지 OCR과 4·11·60·125쪽의
  수동 기준 문구 12개를 검사했다. 전체 125쪽의 문자 오류율을 측정한 것은 아니다.
- 한국어 혼합: 위 125쪽 + USGS 42쪽 + DOCX·HWP·JPEG·TXT·손상 PDF, 총 7개.
  PDF 이미지 125+42개 전체 보존을 검사한다.
- 영문 혼합: USGS 204쪽 + USGS 42쪽 + 같은 나머지 입력 5개, 총 7개.
  USGS 원본에는 기존 OCR 층이 있다. 204쪽 전체의 페이지 OCR 처리를 확인하지만,
  문서당 이미지 128개 제한에 걸린 원본은 위치 경고와 함께 그림 일부만 보존한다.
  이 제한은 전후 동일하다.
- 정상 문서 6개 성공·손상 PDF 1개 개별 실패, 입력 순서, 진행률 단조 증가와 완료/실패 이벤트,
  본문/블록 일관성·페이지 순서·임시 디렉터리 정리를 검사했다.

## 동일 256MiB 설정의 결과

3개 테스트를 각각 3회 실행해 개선 전 9회·개선 후 9회 **모두 통과**했다.
xcresult 요약의 passedTests=3은 고유 테스트 수이며, 반복 실행 수 9와 구분한다.

| 시나리오 | API 중앙값 전→후, 초 | 시간 변화 | 최대 footprint 전→후, MiB | 최대 메모리 변화 |
| --- | ---: | ---: | ---: | ---: |
| 한국어 단일 125쪽 | 96.817→97.090 | 0.3% 증가 | 414.30→390.92 | 5.6% 감소 |
| 한국어 혼합 7개 | 131.365→113.600 | 13.5% 단축 | 376.94→406.16 | **7.8% 증가** |
| 영문 혼합 7개 | 180.874→96.032 | 46.9% 단축 | 513.99→595.55 | **15.9% 증가** |

혼합 배치의 시간 단축을 확인했으나 **기본 256MiB 설정의 최대 메모리 개선은 확인하지 못했다**.
한국어 단일 시간은 거의 같았다. 결과 보유 footprint 중앙값도 한국어 혼합 172.64→180.30MiB,
영문 혼합 287.13→289.74MiB로 줄지 않았다.

한국어 혼합 PDF의 PNG 합계는 66.94→38.43MiB로 **42.6% 감소**했다.
그림 167개·텍스트 해시·블록 수·경고는 유지했다. PNG 크기 감소를 프로세스 최대 메모리 감소와
같은 지표로 설명하지 않는다. 공유 작업 풀의 최대 동시 페이지는 5, 추정 작업 예약은 255.06MiB였고
반환 후 활성 예약·대기 요청은 0이었다. 설정값은 프로세스 전체의 강제 메모리 상한이 아니다.

전후 모든 반복의 입력별 형식·텍스트 SHA-256·글자 수·블록 수·이미지 수·경고 코드/페이지가
일치했다. 이는 수집한 요약의 일치이며, 모든 블록 좌표·OCR 신뢰도와 125쪽 전체의 정답 정확도를
비교했다는 의미는 아니다. 모든 반복에서 결과 순서·진행 이벤트 검사를 통과했다.

## 128MiB 추가 관찰

한국어 혼합 배치를 128MiB 작업 목표로 별도 새 프로세스에서 3회 실행해 **모두 통과**했다.
정상 6개·손상 1개, 이미지 167개와 수집한 결과 요약은 모든 전후 실행과 일치했다.

| API 초, 실행 순서 | 최대 footprint MiB, 실행 순서 | 결과 보유 footprint 중앙값 MiB |
| --- | --- | ---: |
| 113.658 / 114.311 / 114.090 | 390.92 / 412.16 / 393.66 | 188.81 |

API 중앙값은 114.090초, 관측 최대는 412.16MiB다. 공용 최대 진행 페이지는 2,
추정 작업 예약은 109.94MiB였고 반환 후 활성 예약·대기는 0이었다. 모든 실행이 nominal에서 시작했다.
목표 예약을 줄였지만 **기존 배치 대비 프로세스 최대 메모리 감소를 확인하지 못했다**.

이 프로필은 앞선 한국어 단일 문서 없이 배치만 실행했다. 시작 footprint 중앙값은 18.99MiB로,
256MiB 전후 묶음의 한국어 배치 시작값 64.85/65.66MiB와 다르다. 따라서 설정값 변경만의
인과 효과로 비교하지 않는다. 현재 결과로 128MiB를 메모리 개선 기본값으로 권장하거나 적용하지 않았다.
영문 배치의 128MiB 구성은 실행하지 않았다.

**남은 과제:** 혼합 배치의 프로세스 최대 메모리 증가 원인 분석과 감소 검증.
PNG 크기 감소·예약 상한 준수만으로 이 과제가 완료됐다고 처리하지 않는다.

## 단계별 시간

한국어 혼합 배치 안의 125쪽 PDF에 대해 페이지별 경과 시간을 단계별로 합산한 뒤,
실행 3회의 중앙값을 구했다. 단위는 초다. **비동기 작업이 겹치므로 아래 행을 더해서
전체 처리 시간을 구할 수 없고, CPU 사용 시간도 아니다.** 다른 PDF와의 자원 경쟁도 포함한다.

| 단계 | 개선 전·256MiB | 개선 후·256MiB |
| --- | ---: | ---: |
| 페이지 렌더링 | 2.389 | 2.444 |
| 이미지 추출·PNG 인코딩 | 2.234 | 2.752 |
| 이미지 OCR | 62.722 | 196.997 |
| 페이지 OCR | 63.924 | 203.911 |
| 공용 예약 대기 | 이전 지표 없음 | 41.864 |
| PDF 파이프라인 await | 126.687 | 66.414 |
| 결과 조립 | 0.010 | 0.012 |

원본 한국어 PDF는 삽입 이미지가 페이지 전체와 정확히 일치하지 않아 전후 모두
이미지 OCR 125회와 페이지 OCR 125회를 수행했다. 같은 배치의 USGS 42쪽은 개선 후
이미지 OCR 결과를 페이지 OCR에 42회 재사용했다. 한국어 페이지 OCR을 생략해 속도를 올린 것이 아니다.
페이지별 시작 offset·경과 시간과 모든 반복의 수치를 JSON에 함께 보존한다.

## 재현 명령

```sh
python3 "docs/Technical Verification/LabcordParser/Tools/verify_real_world_corpus.py"
python3 "docs/Technical Verification/LabcordParser/Tools/prepare_before_benchmark.py" --output /tmp/ResearchersParserBefore-고유이름
xcodebuild test -project /tmp/ResearchersParserBefore-고유이름/Researchers.xcodeproj \
  -scheme Researchers -configuration Release -derivedDataPath /tmp/ResearchersBeforeDD-고유이름 \
  -destination 'platform=iOS,id=연결된_기기_UDID' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -test-iterations 3 -test-repetition-relaunch-enabled YES \
  -only-testing:ResearchersTests/DocumentReleaseBatchBenchmarkTests/testReleaseMixedBatch \
  -only-testing:ResearchersTests/DocumentReleaseBatchBenchmarkTests/testKoreanMixedBatch \
  -only-testing:ResearchersTests/DocumentKoreanScanTests \
  -resultBundlePath /tmp/ResearchersBefore-고유이름.xcresult \
  DEVELOPMENT_TEAM=사용가능한_팀 CODE_SIGN_STYLE=Automatic ENABLE_TESTABILITY=YES
```

개선 후에는 현재 프로젝트 경로와 별도 DerivedData·xcresult 경로를 사용한다.
128MiB 실행은 `testKoreanMixedBatchConservativeMemory`만 따로 선택한다.
같은 출력 경로를 재사용하지 않는다. Release @testable을 위한 ENABLE_TESTABILITY도 CLI에만 적용한다.

실제 로그·번들:

- `/tmp/issue21-device-before-20261021b.log`, `/tmp/issue21-device-before-20261021b.xcresult`
- `/tmp/issue21-device-after-20261021b.log`, `/tmp/issue21-device-after-20261021b.xcresult`
- `/tmp/issue21-device-memory128-20261021b.log`, `/tmp/issue21-device-memory128-20261021b.xcresult`

## 전체 검증 소요 시간과 원자료

xcresult 시작/종료 시각 기준이며 빌드·설치·냉각 대기·반복 재시작도 포함한다. 시간대는 KST다.

| 단계 | 시각 | 소요 |
| --- | --- | ---: |
| 개선 전 3개 시나리오 × 3회 | 20:19:13→20:52:14 | 33.01분 |
| 개선 후 3개 시나리오 × 3회 | 20:53:39→21:27:52 | 34.21분 |
| 개선 후 한국어 혼합 128MiB × 3회 | 21:28:12→21:40:42 | 12.50분 |

API 시간은 줄었으나 냉각 대기를 포함한 전후 검증 묶음 소요 시간까지 줄어든 것은 아니다.
이 프로토콜은 nominal에서 시작하는 개별 API 비교이며, 냉각 대기 없는 장시간 연속 처리의
지속 성능을 검증한 것이 아니다.

[전체 21회 수치·페이지별 단계 시간·비교 JSON](Device-Batch-Korean-Metrics.json).
본문·그림 바이너리·기기 이름/UDID를 기록하지 않는다.

```sh
python3 "docs/Technical Verification/LabcordParser/Tools/summarize_benchmark.py" \
  --run before-device=/tmp/issue21-device-before-20261021b.xcresult \
  --run after-device=/tmp/issue21-device-after-20261021b.xcresult \
  --run after-conservative-device=/tmp/issue21-device-memory128-20261021b.xcresult \
  --output "docs/Technical Verification/LabcordParser/Reports/Performance/Batch/Device-Batch-Korean-Metrics.json"
```

## 회귀·빌드·린트

- Release 실기기 회귀 **103개 통과**, 테스트 경과 16.990초.
  대용량 성능 클래스 3개와 기존 100쪽 성능 메서드 2개를 제외했다.
  대용량·한국어 성능 검증은 위 21회와 별도다. 취소·부분 실패·배치 순서·예약 반환,
  구형 Office·HWP·TIFF 다중 프레임·PDF 위치·팔레트 픽셀 보존·OCR 재사용 검사를 포함한다.
  `/tmp/issue21-device-regression-20261021c.xcresult`와 같은 이름의 `.log`에 결과가 있다.
- CI 기준 시뮬레이터 빌드 **성공**: `/tmp/issue21-device-followup-ci-build.log`.
- `swiftlint lint --strict`: **94개 파일, 위반 0건**.
  `/tmp/issue21-device-followup-lint.log`.
- 원래 60개·20개 형식과 추가 대용량 PDF 원본 3개의 크기·SHA-256 검증 통과.
- 프로젝트·공유 scheme·Package.resolved의 작업 전후 SHA-256이 동일하다.
  `/tmp/issue21-device-settings-before.sha256`, `/tmp/issue21-device-settings-after.sha256`.
- 집계 스크립트는 실기기·한국어 단일 attachment·모든 반복의 요약 및 단계별 중앙값을
  지원하도록 보완했다. 동일 번들 자기 비교와 서로 다른 실행 환경 비교 제외를 확인했다.
  앱 코드·의존성·라이선스·서명 설정은 추가 변경하지 않았다. 커밋·푸시는 하지 않았다.

실기기 회귀 명령:

```sh
xcodebuild test -project Researchers.xcodeproj -scheme Researchers -configuration Release \
  -derivedDataPath /tmp/issue21-device-after-dd \
  -destination 'platform=iOS,id=연결된_기기_UDID' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -skip-testing:ResearchersTests/DocumentLargeScanTests \
  -skip-testing:ResearchersTests/DocumentKoreanScanTests \
  -skip-testing:ResearchersTests/DocumentReleaseBatchBenchmarkTests \
  -skip-testing:ResearchersTests/DocumentPerformanceTests/testHundredPagePDFReportsTimeAndSampledFootprint \
  -skip-testing:ResearchersTests/DocumentPDFParallelPerformanceTests/testCompareSerialAndParallelStageTimesOnHundredPages \
  -resultBundlePath /tmp/ResearchersDeviceRegression-고유이름.xcresult \
  DEVELOPMENT_TEAM=사용가능한_팀 CODE_SIGN_STYLE=Automatic ENABLE_TESTABILITY=YES

xcodebuild build -project Researchers.xcodeproj -scheme Researchers \
  -destination 'generic/platform=iOS Simulator'
swiftlint lint --strict
```

처음 회귀 명령에 `-test-iterations 1`을 명시하자 Xcode가 2회 이상만 허용한다며 실행 전
종료 코드 64로 거부했다. 해당 옵션을 제거한 위 명령으로 실제 103개를 실행했다.
그 CLI 오류는 `/tmp/issue21-device-regression-20261021b.log`에 보존하며 테스트 실행 결과와 구분한다.

후속 원인 분석과 동일 결과 지문을 사용한 별도 전후 3회 비교는
[최대 메모리 분석·개선](Memory-Peak-Optimization.md)에 기록했다. 이 문서의 과거 수치는 보존한다.
