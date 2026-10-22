# 실기기 성능·취소 검증 계획

이 문서는 계획 수립 시점의 기록이다. 이후 실기기 실행 시도·계측 결과는
[잔여 보완 검증](../../Review/Remainder-Verification.md)을 따른다.

## 범위와 현재 상태

UI를 추가하지 않고 기존 ResearchersTests와 Researchers scheme으로 검증한다.
시뮬레이터 시간은 실기기 성능값으로 사용하지 않는다. 이번 작업은 계획 작성이며,
기기 설치·서명 변경·실기기 XCTest·Instruments 측정은 실행하지 않았다.
2026-10-21 `xcrun devicectl list devices`에서 연결된 iPhone 17 실기기를 확인했다.
연결 여부만으로 개발자 모드·잠금 해제·서명·테스트 실행 가능 여부를 보장하지 않는다.

## 실행 전 기록

- 기기 모델·메모리 등급·iOS 빌드, 앱 커밋과 미커밋 diff, 패키지 버전, Release/Debug 구성을 기록한다.
- 최소 지원 iOS 27 기기와 주력 기기에서 각각 수행한다. 최소 메모리 기기의 실제 보유 여부를 먼저 확인한다.
- 재시작 후 배터리 50% 이상, 저전력 모드 끔, 열 상태 nominal에서 시작한다.
- 네트워크를 끄고 번들 원본만 사용한다. 다운로드·업로드·문서 본문 로깅을 하지 않는다.
- 시험 식별자, SHA-256, 입력 바이트, 픽셀/페이지/그림 수와 수치만 기록한다.

## 실행 명령

기존 설정의 서명을 사용하며 인증서·팀·프로비저닝을 자동 변경하지 않는다.
UDID는 실행 시 `xcrun devicectl list devices`로 확인한 값을 쓴다.

```sh
xcrun devicectl list devices
xcodebuild test -project Researchers.xcodeproj -scheme Researchers \
  -configuration Release -destination 'platform=iOS,id=실제_UDID' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /tmp/ResearchersDeviceTests-고유이름.xcresult
```

서명·기기 신뢰 오류가 나면 그대로 기록하고 중단한다. `-allowProvisioningUpdates`를
임의로 추가하지 않는다. 최초 설치·Vision 준비 비용을 포함한 cold 실행과 이후 warm
실행을 분리한다. UI 자동화·새 화면·운영 문서 반입이 필요하지 않다.

## 시험 행렬

| 구간 | 입력 | 반복·관찰 |
| --- | --- | --- |
| 기준 | 외부 코퍼스 60개 | cold 1회, warm 5회; 기존 정답 검사 유지 |
| PDF | 자체 생성 일반·스캔·혼합 1/10/100페이지 | 원본 페이지·그림 수, 중복 OCR, 결과 크기 |
| 래스터 | 자체 생성 1/10/39MP, TIFF 2/20프레임 | 디코딩/인식 시간, 프레임 위치·자원 상한 |
| Office/HWP | 원본 3개씩, 자체 생성 표·그림 확대본 | 임시 파일, 백엔드 동기 구간, 부분 결과 |
| 배치 | 텍스트·스캔·Office 혼합 10개, 동시성 1/2 | 입력 순서·개별 실패·peak footprint |
| 제한 | 입력/압축 해제/픽셀/그림/페이지 상한 바로 아래·위 | 명확한 실패 또는 위치 경고; 프로세스 생존 |
| 취소 | 실행 전, 추출 시작, OCR 중간, 배치 중간 | 취소 요청→Task 종료 지연, 완료된 개별 결과 |
| 반복 | 동일 문서 20회, 결과 해제 후 idle 10초 | 지속 증가·임시 폴더 누적·메모리 경고 |

확대 입력은 테스트에서 직접 생성하고 산출물 해시·생성 매개변수를 기록한다.
고정 문서를 단순 복사한 배치와 실제 페이지가 증가한 문서를 구분한다. 현재 60개 원본이
대용량 스트레스 입력을 대체한다고 주장하지 않는다. 이 행렬의 확대 입력·계측용 코드는
아직 추가하지 않았으며 실기기 측정 단계에서 기존 fixture builder를 확장한다.

## 계측 방법

1. API 호출 직전부터 반환까지 ContinuousClock으로 벽시계 시간을 잰다.
   5회 표본은 각각과 중앙값·최댓값을 보고한다. p95는 30회 이상 실행한 경우만 보고한다.
2. XCTest clock/memory metric과 Instruments Allocations·VM Tracker를 함께 사용한다.
   baseline, 최대 physical footprint, 결과 보유 중, 결과 해제 후 idle 값을 구분한다.
   Swift heap만을 전체 프로세스 메모리로 보고하지 않는다.
3. 취소는 별도 작업에서 monotonic timestamp를 찍고 `task.cancel()`부터 `await task.value`
   종료까지 잰다. 인식/백엔드 내부 호출은 동기이므로 호출 중 즉시 중단을 전제하지 않는다.
4. Office 임시 경로 `DocumentParsing-*`의 실행 전·후 집합을 비교한다. 다른 실행의
   폴더는 지우지 않는다. 성공·손상·취소 후 모두 확인한다.
5. 배치 완료·실패·취소 이벤트는 inputIndex·phase·수치만 수집한다. 프레임워크 내부 캐시와
   이번 파서가 만든 파일을 구분하고 문서 원문·OCR 문자열을 기기 로그에 남기지 않는다.

## 판정과 결과표

기존 정답·입력 순서·상한·취소 오류·임시 파일 정리 검사는 필수 통과 조건이다.
OS 강제 종료·무한 대기·원본 변경·원격 접근·민감 정보 로그는 실패로 기록한다.
메모리 MB·시간 ms·취소 지연의 제품 합격선은 측정 전에 대상 기기별로 정한다.
현재 근거 없이 임의의 수치를 제품 보장치로 정하지 않는다.

| 기기/OS | 입력 ID/해시 | 반복/cold | ms | peak footprint MB | idle MB | 취소 지연 ms | 결과/경고 | 임시 파일 차이 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 미측정 | — | — | — | — | — | — | — | — |

측정 후 Instruments trace·xcresult는 로컬에 보관하고 문서에는 수치와 비식별 ID만 옮긴다.
메모리 상한 기본값 조정은 실제 최저 사양 결과와 함께 별도 변경으로 검토한다.
