# 잔여 파싱 기능 보완 및 검증

이후 임시 개발 팀 지정으로 실기기 실행을 완료했다. 서명 차단 상태와 이전 숫자 OCR
설명은 당시 기록이며, 최신 상태는 [실기기 검증](Physical-Device-Verification.md)을 따른다.

2026-10-21. 병합 셀·그림 설명·논리 앵커·금액 OCR을 구현하고 계측 테스트를 추가했다.
기존 변경을 보존했으며 의존성·OS 최소 버전·Swift 언어 모드·서명 설정은 변경하지 않았다.

## 구현

### HWP·HWPX

- 표 셀의 rowSpan·columnSpan을 보존한다. 누리 문서의 열 3개 병합 셀을 검사한다.
- 문단·셀의 그림 컨트롤에서 BinData ID를 연결한다. HWP의 일반 도형 컨트롤과
  HWPX의 picture 컨트롤을 처리하며, 기존에 비어 있던 셀의 그림도 찾는다.
- 그림 설명 3개를 sourceDescription과 image 블록에 보존한다. 설명은 전체 본문에
  끼워 넣지 않는다. 표별 경로·행·열·문단 위치를 전달한다.
- 같은 BinData의 반복 참조는 배치 블록을 남기고 OCR 중복을 방지한다.
- 앵커 없는 바이너리는 별도로 추출한다. 부동 개체의 실제 페이지 조판은 하지 않으므로
  문단·셀 앵커가 있어도 페이지 읽기 순서 불확실성 경고를 보존한다.
- 원본 HWPX 설명을 읽는 ZIP reader는 실제 inflate 크기·CRC·로컬 헤더를 검사한다.
  경로 탈출·상한·중단·엔티티·DTD 방어 테스트를 추가했다. 시스템 zlib를 사용하며
  새 의존성·임시 압축 해제 파일을 만들지 않는다.
- 복구된 메모 문단도 일반 문단·구역 복구처럼 extractionFailed 경고로 분류한다.

### 숫자 OCR

확대 1/2/3배와 언어 교정 켜기/끄기, 개별 영역 확대 2/4/6배, 투영 임계값
100/150/180/210과 원본 후보를 비교했다. 비교 결과를 XCTest JSON 첨부에 보존한다.
단순 확대나 신뢰도가 높은 후보가 항상 정확하지 않았으므로 그 정책을 일괄 적용하지 않는다.

작은 저신뢰 숫자에 한해 다른 픽셀 투영의 Vision 결과를 확인한다. 통화 기호 이후
숫자·쉼표·소수점이 그대로이고 신뢰도가 떨어지지 않을 때만 새 기호를 채택한다.
최초 인식문 ocrOriginalText를 보존하고 전체 텍스트는 최종 블록에서 생성한다.
금액·OCR 텍스트를 앱 로그에 추가하지 않는다.

누리 그림의 설명/앵커와 금액 3개 회귀 검사는 원본 기반이며 제품 전체의 완전한
형식 호환성·OCR 정확도 보장을 뜻하지 않는다. 픽셀 재인식도 오인식할 수 있고,
확대·회전·서체·색상·다른 금액에 대한 독립 정답 코퍼스 확대가 필요하다.

## 실기기 실행 상태

실제 연결된 iPhone 17을 대상으로 다음 명령을 실행했다.

```sh
xcodebuild test -project Researchers.xcodeproj -scheme Researchers \
  -destination 'platform=iOS,id=00008150-001D58E23C45401C' -destination-timeout 15 \
  -only-testing:ResearchersTests/DocumentNumericOCRTests \
  -collect-test-diagnostics never -resultBundlePath /tmp/issue21-device-attempt.xcresult
```

**서명 단계 실패**: Researchers·ResearchersTests에 개발 팀이 지정되지 않았고,
워치 앱의 개발 프로비저닝 프로파일이 없다. 기기에 설치되거나 XCTest가 실행되지 않았다.
로그 `/tmp/issue21-device-attempt.log`. 저장소 설정·Apple 개발자 프로파일을 임의로
변경하지 않았다. 사용할 개발 팀과 이번 실행/저장소 반영 여부를 사용자에게 요청했다.
실기기 최대 메모리·열 상태·취소 지연 검증을 완료했다고 보고하지 않는다.

## 계측 테스트

`DocumentPerformanceTests`는 기존 scheme에서 다음을 검사한다.

- 자체 생성 100페이지 PDF를 5회 처리하고 각 호출 시간·결과 페이지 수를 기록한다.
- 20ms 간격으로 task_vm_info의 physical footprint를 표본 수집한다. 표본 최댓값은
  정확한 순간 최대값이나 Swift heap 크기와 구분한다. baseline·완료 후 값도 기록한다.
- HWPX·구형 Office 성공 및 손상 Office 실패 후 파서 임시 폴더 집합을 대조한다.
- 20프레임 TIFF에서 OCR 시작 후 20ms에 취소하고 요청→반환 지연을 측정한다.
  OCR 시작 이벤트 뒤의 지연 요청이며 Vision 내부의 정확한 실행 위치를 보장하지 않는다.
- 환경을 simulator/physical-device로 명시하고 본문·개인 파일을 첨부하지 않는다.

[실기기 계획](Device-Performance-Plan.md)의 전체 행렬을 수행했다는 뜻은 아니다.
반복·표본 메모리·취소 자동 계측을 준비하고 시뮬레이터에서 실제 실행한 범위를 보고한다.

## 검증 결과

- 누리 HWP/HWPX: 원본 병합 셀·그림 설명 3개·그림 4개의 논리 앵커 검사 통과.
  그림 중 3개는 표 셀에 있고 하나는 일반 문단에 있다. 처음 셀 그림 2개로 작성한
  기대값은 XML/실제 컨트롤 대조 후 3개로 바로잡았다.
- 금액 OCR: 기존 1/3에서 **3/3**, 합산 문자 오류율 **2/22에서 0/22**.
  [원래 측정](Numeric-OCR-Metrics.json)과 [개선 후 측정](Numeric-OCR-Enhanced-Metrics.json)을
  따로 보존한다. 이 작은 원본의 개선이며 일반 정확도 100% 주장이 아니다.
- 성능 시험: 100페이지 PDF 5회 모두 페이지 100개·블록 100개 결과 검사 통과.
  호출 시간은 68.126/56.654/46.001/44.534/50.103초. 첫 반복 이후 4회 중앙값
  **48.052초**. 앞선 XCTest에서 Vision이 이미 사용됐으므로 첫 반복을 cold 실행으로
  부르지 않는다. 모든 페이지를 렌더링·OCR하는 현 정책의 비용이 포함된다.
- 시뮬레이터 프로세스 physical footprint: baseline **279.71MiB**, 표본 최대
  **316.47MiB**, 마지막 결과 처리 후 **297.83MiB**. 이전 테스트의 캐시·테스트 호스트도
  포함하므로 파서 단독 메모리 또는 실기기 요구량으로 일반화하지 않는다.
  [성능 수치](Simulator-Performance-Metrics.json).
- 20프레임 TIFF 취소 요청→반환 **292ms**, 임시 폴더 추가 0개.
  [취소·정리 수치](Simulator-Cancellation-Metrics.json). 단일 시행이며 실기기 보장치가 아니다.
- 실기기는 서명 단계에서 차단되어 성능·정확도·취소 결과가 없다.

최초 전체 실행은 84개 중 XML 엔티티 선언 거부 검사 1개가 실패했다. Foundation이
외부 엔티티를 해석하지 않았어도 선언 자체를 거부하지는 않아 UTF-8/16/32 선언을
사전 차단하도록 보완했다. 이후 네임스페이스·중복 ID와 메모 복구 회귀 검사도 추가했다.
최종 일반 회귀 검사는 100페이지 반복 시험만 제외하고 실행한다. 해당 시험은 앞선
실행에서 이미 별도로 성공했으며, PDF 파싱 구현은 이 작업에서 변경하지 않았다.

```sh
xcodebuild test -project Researchers.xcodeproj -scheme Researchers \
  -destination 'platform=iOS Simulator,id=46BECA1F-89C4-42E2-B9DD-5F6CB316E62B' \
  -parallel-testing-enabled NO \
  -skip-testing:ResearchersTests/DocumentPerformanceTests/testHundredPagePDFReportsTimeAndSampledFootprint \
  -collect-test-diagnostics never -resultBundlePath /tmp/issue21-remainder-delivery.xcresult
xcodebuild build -project Researchers.xcodeproj -scheme Researchers \
  -destination 'generic/platform=iOS Simulator'
swiftlint lint --strict
python3 "docs/Technical Verification/LabcordParser/Tools/verify_real_world_corpus.py"
```

전체 100페이지 시험을 다시 실행하려면 `-skip-testing`을 빼거나 그 메서드를
`-only-testing`으로 지정하고 새로운 xcresult 경로를 쓴다. 이 환경에서 약 265초가
걸리므로 일반 회귀 실행과 구분했다. 성능 시험 원본 xcresult는
`/tmp/issue21-remainder-full.xcresult`이며 그 실행의 엔티티 거부 실패도 그대로 남겨 둔다.

추가·변경 파일은 HWP 파서/문맥/이미지/설명 보완, bounded ZIP reader, 이미지·OCR 결과
모델, 숫자 OCR 보완, 관련 회귀·비교·계측 테스트, 정답 생성기와 문서다.
상용 사용·소스 공개 조건을 바꾸는 새 패키지 추가는 없으며 기존 의존성과 샘플의 고지가
계속 적용된다. 커밋·푸시는 실행하지 않았다.

최종 회귀 XCTest: **85개 통과·실패 0개**, 39.805초. 앞서 따로 실행한 100페이지
성능 메서드 1개도 통과했다. 두 실행을 합쳐 현재 테스트 메서드 86개를 검증했으며,
동일한 한 번의 전체 실행에서 86개가 통과했다고 표현하지 않는다.
최종 strict lint: **76개 파일·위반 0개**. 원본 60개 해시·수량과 `git diff --check` 통과.
로그는 `/tmp/issue21-remainder-delivery.log`,
`/tmp/issue21-remainder-delivery-lint.log`에 있다.

CI 앱 빌드 명령도 성공했다. 빌드 로그: `/tmp/issue21-remainder-delivery-build.log`.
