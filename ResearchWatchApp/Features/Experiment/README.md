# Watch 실험 화면 통합

`WatchExperimentFeature`가 선택·권한·준비·시작·중단·재개·종료·연결 상태를 관리한다.
View는 Action만 전달한다. 기존 배터리·기기명 startup은 유지한다.

## #173 소비 계약

`LabcordWatchOS`의 `DependencyValues.watchExperimentClient`를 사용한다.
`send(WatchExperimentCommand) async throws -> WatchExperimentResponse`,
`snapshots() async -> AsyncStream<WatchExperimentSnapshot>`,
`isReachable() async -> Bool`이 필요하다. 이 checkout에는 DTO만 있으며 Client 구현은
core commit 통합 후 컴파일한다. 성공을 반환하는 대체 Client는 넣지 않는다.

- list → 선택 ID의 snapshot → 마이크 권한 → prepareStart → startToken → 준비 3초 → start.
- 준비/시작의 정확한 카운트다운 시점은 설계 문서에서 미확정이다. 기존 Watch는 Hello World뿐이다.
  Figma의 준비/시작 화면 순서를 따라 **prepareStart 성공 후, start 전** 3초를 사용한다.
  취소·앱 비활성화 시 start를 보내지 않으며 새 prepareStart가 필요하다. 팀 확인 대상이다.
- 전달 3초 초과는 실행 여부 불명이다. 원래 requestID를 유지한다.
  requestStatus는 새 envelope requestID와 `targetID = 원래 requestID`를 보낸다.
  응답 requestID는 조회 envelope ID여야 한다. core와 이 의미를 대조해야 한다.
- received/processing은 완료가 아니다. 1초 간격 requestStatus로 결과를 확인한다.
  snapshots는 상태 동기화 용도이며 요청 완료를 추측하지 않는다.
- 선택 ID·stream 세대·응답 ID·실험별 revision으로 오래된 결과를 차단한다.
  비활성화 시 Effect를 취소하고 미확정 요청을 유지한다. 재활성화/재연결 시 상태를 조회한다.
- iPhone의 전면/백그라운드/잠금 처리는 승인된 dobest 정책에 따른 core 결과를 표시한다.
  phoneBusy/activeExperimentConflict는 Watch에서 우회하지 않는다.
- 실험 중단/종료 완료는 기록 영구 저장 완료가 아니다. #174 저장 ACK가 필요하다.

## 디자인

2026-11-05 Figma `v6cxQ2I6zURWYQaG5pnuBL`의 502:12602, 502:12297 및
593:9529, 593:9556, 587:11233, 593:10004, 593:10034, 593:10038,
593:10073, 593:10103, 593:10111, 1592:9926을 읽기 전용 조회했다.
Watch용 공통 컴포넌트/리소스가 저장소에 없어 native SwiftUI의 버튼·스크롤·폰트를 사용한다.
Figma의 고정 시각/스크롤바는 시스템 UI에 맡긴다. 준비 링은 Figma에서 내려받은 SVG를
WatchAssets의 WatchPreparationRing 이미지로 사용한다. 실기기 렌더·픽셀 일치는 미검증이다. 중단/연결 끊김 문구는 승인된 저장·원본 보존 요구를 따른다.

## 검증

이 단계에서 SwiftLint strict, Swift parser, diff 공백 검사를 수행한다.
Client 미통합 상태의 파싱은 타입검사·빌드·통신 검증이 아니다.
공유 Simulator를 사용하지 않는다. core 통합 후 Watch 빌드와 페어링 기기 검증이 남는다.

## #171・#174 기록 통합 계약

`WatchExperimentFeature(recordingBridge:)`는 선택적인 `WatchRecordingUIBridge`를 받는다.
앱 Store에는 아직 bridge를 넣지 않았다. 실제 구현이 없으면 기록 버튼을 비활성화하고
통합 필요 안내를 표시한다. 빈 구현이나 성공을 반환하는 대체 구현은 없다.

`WatchRecordingUIBridge.perform`은 startVoice/stopVoice/retry/reconcile/stopForExperiment 입력을,
`updates`는 실제 `WatchRecordPresentation` 스트림을 제공해야 한다. 이 타입은 화면 측 계약 제안이다.
#174의 실제 모델/API와 대조해 adapter를 공급한다. 이벤트의 record ID와 experiment ID가 고정되고
revision이 증가해야 한다. 원본 보관 여부·partial/final 전사·수정 충돌·오류 설명을 실제 상태로 채운다.
앱 재활성화 시 reconcile은 보관 원본과 미확정 저장 결과를 재조회한다.

- 사진/영상/확인/취소는 기존 takePhoto/startVideo/stopVideo/confirmRecord/cancelRecord를 사용한다.
  `targetID`로 Watch가 생성한 record ID를 전달하는 계약은 core/#174와 합의가 필요하다.
- command completed는 실행 확인이다. 최종 저장 UI는 #174가 영구 저장 ACK를 검증한 뒤 보낸
  `phase = saved`에서만 표시한다. cancelRecord도 실제 취소 이벤트 전에는 완료로 표시하지 않는다.
- review + canAutoSave 이벤트에서만 화면 Feature가 자동 저장 3초를 관리한다.
  영상은 실제 미리보기 종료 뒤 이 이벤트를 보내야 한다. #174에서 같은 자동 저장을 중복 실행하지 않는다.
  비활성화 시 자동 저장 카운트다운은 취소하고 검토 원본을 유지한다. 복귀 후 수동 저장 가능하다.
- close는 화면만 닫는다. 녹음/원본/전송/저장 상태를 삭제하지 않는다.
- stopForExperiment는 Watch 녹음을 종료하고 확보 원본을 보관한 뒤 반환해야 한다.
  그 뒤 pause/complete를 전송한다. iPhone 영상 종료·저장/타이머 정리는 core/#174 책임이다.
  실패하면 실험 중단·종료 성공으로 진행하지 않는다. 연결 끊김은 녹음 중지 명령이 아니다.
- 재시도는 동일 record ID의 보관 원본으로 복구한다. 새 촬영/음성 토글로 해석하지 않는다.
- .saved/.cancelled는 화면에서 종결 상태다. 이전 revision과 다른 실험·종류의 동일 ID 이벤트는 무시한다.

## 타이머

WatchTimerSnapshot.remaining(at:)을 그대로 사용한다. paused는 로컬 시간이 지나도 줄지 않는다.
상태 변경은 낙관적으로 반영하지 않고 iPhone snapshot으로 보정한다. 실행 중 0초에 도달해도
최종 완료 상태는 iPhone의 finished를 기다린다. List row에 swipeActions 삭제를 연결했다.

DTO에 ExperimentMode가 없어 실제 모드를 임의로 추론하지 않는다. 전달된 프로토콜 타이머와
자유 타이머 선택을 함께 표시한다. 프로토콜 타이머의 원래 순서·중복 시간·개수를 보존한다.
같은 초 값은 출현 순번과 함께 안정적인 표시 ID를 구성한다.
정확한 모드별 노출에는 #173 snapshot에 모드 필드 또는 별도 합의된 조회가 필요하다.
개별 타이머 종료·완료 확인·스와이프 삭제는 현재 유일한 종료 API인 deleteTimer를 사용한다.
종료 시 기록 보존과 삭제 의미를 구분해야 한다면 core의 별도 op/합의가 필요하다.

## 남은 검증

실제 Watch 빌드, 화면 크기별 렌더, 페어링 기기의 연결/저장/권한/카메라 복구,
#174 원본 보존·전사·최종 ACK, AssistiveTouch 노출·배정·실행은 미실행이다.
Intent나 가짜 손 제스처 인식은 구현하지 않았다.

2026-11-05 로컬 검증: SwiftLint strict 15개 Swift 파일 0 위반, Swift parser 통과,
준비 링 watchsimulator actool 컴파일 통과. 저장소 외부 FocusedChecks에서 실제 소스 심볼을
symlink로 참조해 macOS TCA TestStore와 타이머/표시 규칙 테스트 8개를 실행했다.
최종 저장 ACK 전 대기, 3초 자동 저장, background 취소, close 원본 유지, 오래된/다른 실험
이벤트 차단, 동일 ID 재시도를 검증했다. 이는 Watch 앱의 타입검사·빌드·통신 성공 증거가 아니다.

실험/기록 stream 종료 시 새 입력을 차단하고 재연결 경로를 표시한다. 앱 비활성화 시 조회 요청은
버리고 재활성화에 새로 조회한다. 변경 명령은 실행 여부가 불명확하므로 원래 ID를 보존한다.
Client의 send는 수신/처리 중이면 그 phase를 반환해야 화면에서 전달 ACK와 처리 대기를 구분할 수 있다.

외부 harness는 저장소와 같은 TCA 1.26.2 소스를 사용하지만 전이 의존성은 별도로 해결한다.
저장소 잠금 버전으로 맞추는 별도 시도는 SwiftPM dependency trait 해석 오류로 실패했다.
따라서 집중 테스트 통과를 제품 Package.resolved 구성 검증으로 확대하지 않는다.

## 취소 의도와 상태 수신 종료

기록별 저장·취소 의도는 최종 저장/취소 결과가 올 때까지 유지한다. 더 높은 revision의 검토 상태가 늦게 도착해도 취소를 자동 저장으로 뒤집지 않는다. 기록 스트림이 끊기면 자동 저장 Effect를 취소하고, 다시 연결되기 전 확인·취소·이미 큐에 들어온 자동 저장 입력을 실행하지 않는다.

외부 macOS 집중 검사에서 기존 8개와 취소 이후 review 역전·기록 스트림 종료 2개를 확인했다. 제품 잠금 전이 의존성과 다른 harness이므로 Watch 제품 빌드·실기기 검증을 대신하지 않는다. 결과는 QA의 `watch-ui-review-fixes/test-first.log`에 보존한다.

## 복구 이동과 늦은 실행 방어

미확정 기록에 의한 이동 차단은 현재 선택한 실험에만 적용한다. 선택 화면에서는 복구 기록이 속한 실험으로 들어가 처리할 수 있다. 촬영 전 카메라 불가·권한 거부가 확정된 사진/영상 요청은 새 ID로 명시적으로 재촬영할 수 있지만, 타임아웃처럼 실제 처리 여부가 불명확하면 기존 ID를 유지해 상태를 먼저 조회한다.

준비 요청 중 닫기·상태 수신 종료·전달 시간 초과는 해당 준비 의도를 무효화한다. 이미 전송한 변경 명령의 처리 여부는 보존하며 새 명령으로 자동 재실행하지 않는다. 상태 관찰이 유효하지 않으면 남아 있던 시작 카운트다운·중단 완료 callback으로 명령을 발행하지 않는다.

기록·부모 Reducer의 집중 검사 17개가 통과했다. 부모 검사에서는 실제 통신 대신 명시적인 테스트 Dependency를 사용하며, 제품 Watch 앱 타입검사나 WCSession 성공을 입증하지 않는다. 검사·소스 링크·로그는 QA의 `watch-ui-review-fixes`에 보존한다.
