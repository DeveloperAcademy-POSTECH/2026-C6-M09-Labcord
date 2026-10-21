# 실기기 문서 파싱 검증

2026-10-21. 개발 팀은 실행 시 명령행에서만 지정했다.
프로젝트·공유 scheme·Package.resolved의 실행 전후 SHA-256이 동일하다.
저장소의 개발 팀·서명·프로비저닝 설정은 바꾸지 않았다.
연결 기기를 포함하는 기존 개발 프로파일을 사용했다.

## 환경과 실행

- 기기: iPhone 17 (iPhone18,3), iOS 27.0.1 (24A446), 유선 연결, 개발자 모드 활성.
- Xcode 27.1, Researchers scheme, Debug XCTest, 병렬 실행 끔.
- 최소 iOS 27.0 및 Swift 언어 모드 5.0 유지. 새 패키지 추가 없음.
- 앱과 테스트 설치·서명 후 실제 기기에서 실행했다. 워치 타깃도 서명·빌드했지만
  워치 앱의 기능 테스트를 수행한 것은 아니다.
- 외부 문서 다운로드 없이 기존 번들 샘플과 자체 생성 입력을 사용했다.
  비행기 모드·열 상태·배터리를 통제한 실험은 아니며 네트워크 패킷 계측도 하지 않았다.

실제 선택한 개발 팀 ID는 저장소 설정에 넣지 않았다. 재실행할 때 다음 변수와
연결된 기기의 UDID를 실행 환경에서 지정한다.

```sh
xcodebuild test -project Researchers.xcodeproj -scheme Researchers \
  -destination "platform=iOS,id=$DEVICE_UDID" \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /tmp/ResearchersDeviceTests-새로운경로.xcresult \
  DEVELOPMENT_TEAM="$DEVICE_TEAM_ID" CODE_SIGN_STYLE=Automatic
```

최초 시도에는 `-allowProvisioningUpdates`도 허용했지만 사용 가능한 기존 wildcard
개발 프로파일로 서명했다. 이후 검증에서는 이 옵션 없이 같은 프로파일로 실행했다.
개발 팀 선택을 프로젝트 파일이나 xcconfig에 저장하지 않았다.

## 발견한 오류와 수정

첫 실기기 전체 실행은 86개 중 금액 OCR 테스트 1개에서 assertion 3개가 실패했다.
이전에 시뮬레이터에서 통과한 작은 금액이 실제 기기에서 `5661.37`로 인식됐다.
높은 신뢰도·단순 확대·CPU 실행 전환이 정확도를 보장하지 않음도 비교했다.

실기기 결과에 따라 다음을 보완했다.

1. 숫자 재인식은 하나의 밝기 임계값에만 의존하지 않고 150/140/160의 좁은 범위를
   최대 3회 확인한다. 이미 해소한 블록은 다시 바꾸지 않고 남은 대상이 없으면 중단한다.
2. 새 OCR이 실제 `$`를 반환하고 이후 숫자·쉼표·소수점이 동일하며 신뢰도가
   떨어지지 않은 경우에만 채택한다. 숫자 값 자체를 교정하거나 문자열로 `$`를 만들지 않는다.
3. 최초 인식문은 계속 `ocrOriginalText`로 보존한다. 기기·OS가 처음부터 올바르게
   읽는 경우에도 통과하도록, 고정 보완 횟수 2회를 요구하던 검사를 원문 보존 검사로 바꿨다.
4. CPU/자동 실행과 전처리 비교 테스트 2개를 추가했다. 운영 OCR의 실행 장치를 CPU로
   강제하지 않는다. 새 의존성 없이 Vision/CoreML 시스템 API로 비교했다.

[금액 결과](Device-Numeric-OCR-Metrics.json),
[실행 장치 비교](Device-OCR-Compute-Comparison.json),
[밝기 비교](Device-OCR-Contrast-Comparison.json).

## 최종 실기기 결과

**88개 테스트 통과, 실패 0건**, XCTest 실행 **47.793초**.
20개 형식 × 3개 외부 원본, 구조·부분 정답·위치·읽기 순서·한영 OCR·위험 입력·자원
상한·취소와 성능 테스트를 기존 scheme에서 실행했다.
금액 3개는 모두 일치했고 문자 편집 거리는 0이었다. 작은 샘플 3개의 결과이며
일반 문서의 OCR 정확도 100%를 의미하지 않는다.

린트 정리를 위한 동작이 같은 함수 분리 후에는 실제 기기에서 숫자 OCR 4개를 다시
실행해 통과했다. 전체 88개 실행과 이 후속 실행은 별도 xcresult에 보존했다.

### 100페이지 PDF 5회

[성능 원자료](Device-Performance-Metrics.json).
자체 생성 100페이지·57,468바이트 PDF를 매번 새로 파싱하고 페이지·블록 100개를 검사했다.
본문이 있는 모든 페이지를 렌더링·OCR하는 현재 구현의 비용이 포함된다.

| 반복 | API 처리 초 |
| --- | --- |
| 1 | 7.451 |
| 2 | 7.757 |
| 3 | 7.812 |
| 4 | 7.739 |
| 5 | 7.798 |

5회 중앙값 **7.757초**, 첫 반복 이후 4회 중앙값 **7.778초**.
앞선 테스트에서 프레임워크·Vision이 이미 사용됐으므로 cold 실행으로 부르지 않는다.
표본이 5회여서 p95는 보고하지 않는다.

프로세스 physical footprint: 시작 **362.74MiB**, 20ms 간격 표본 최대 **410.92MiB**,
마지막 처리 뒤 **185.39MiB**. 입력·테스트 호스트·이전 OCR 캐시도 포함하며, 표본 사이
순간 최대값은 놓칠 수 있다. 시작보다 종료 메모리가 줄었다는 사실만으로 누수 없음이나
파서 단독 메모리 사용량을 주장하지 않는다. 최소 메모리 기기의 안전 상한도 아니다.

### 취소·임시 파일

[취소·정리 원자료](Device-Cancellation-Metrics.json).
20프레임 TIFF에서 인식 시작 이벤트 후 20ms에 취소를 요청했다.
요청→반환 지연 **12.23ms**, 취소 오류 전달 검사 통과.
Vision 내부의 정확한 실행 위치를 계측한 것은 아니며 단일 시행이다.
HWPX·구형 Office 성공·손상 Office 실패 후 파서 임시 폴더의 추가는 0개였다.

## 증거와 남은 검증 범위

- 전체 실행: `/tmp/issue21-device-final.xcresult`, `/tmp/issue21-device-final.log`.
- 함수 정리 후 숫자 재검증: `/tmp/issue21-device-delivery.xcresult`,
  `/tmp/issue21-device-delivery.log`.
- 최초 실패 실행: `/tmp/issue21-device-validation.xcresult`; 실패 기록을 삭제하지 않았다.
- 서명 설정 파일 해시: `/tmp/issue21-device-settings-before.sha256`,
  `/tmp/issue21-device-settings-final.sha256`.

[실기기 계획](Device-Performance-Plan.md)의 전체 행렬을 완료한 것은 아니다.
최저 사양 기기·장시간 반복·열/배터리 통제·Release 구성·Instruments 추적과 더 많은
금액·글꼴·언어 정답은 별도 검증 범위다. 이번 결과는 위 iPhone 17과 Debug 자동 검증에
한정된다. 부동 그림의 실제 페이지 조판 순서는 계속 위치 기반 경고로 보고한다.

## 시뮬레이터 회귀·린트

같은 최종 코드로 시뮬레이터 회귀 **87개 통과, 실패 0건**, 45.622초.
100페이지 반복 성능 시험만 제외했고 해당 시험은 이번 실기기 전체 실행에 포함했다.
strict lint **77개 파일·위반 0건**, 외부 원본 60개 해시·수량 및 `git diff --check` 통과.
시뮬레이터 xcresult: `/tmp/issue21-device-change-simulator.xcresult`.
린트 로그: `/tmp/issue21-device-final-lint.log`.

CI 명령 그대로 실행한 앱 빌드도 성공했다. 로그: `/tmp/issue21-device-followup-build.log`.
