# Watch 기능 구현과 리뷰 경계

2026-11-05 확정된 7개 구성의 누적 기능 상태다. 기존 제품 소스를 재배치하며 새 의존성·테스트 타깃·
기능을 추가하지 않는다. 이 문서는 작업 이력 대신 현재 head에서 제공하는 계약과 다음 연결 경계를 기록한다.
선행 #216(`feat/#167-Devin-prepared`, `41ff3c2`) 위에 #173 → #174 → #268 → #269 → #170 → #171 → #270 순서다.
선행 PR 변경·머지는 이 작업에 포함하지 않는다. 원격 게시 없이 로컬 초안만 준비한다.

### #173 통신·중복 방어와 iPhone 시작

`WatchExperimentCommand/Response/Snapshot`과 `WatchExperimentTransport`, 양쪽 `WCSession` 및
`WatchExperimentClient`를 연결한다. 배터리·기기명 전송은 유지한다. `received`는 수신 ACK,
`processing`은 실행 중, `completed`는 명령 결과다. 기록의 영구 저장 ACK와 구분한다.

변경 요청은 실행 전 보호된 journal에 원자적으로 남긴다. 같은 ID·payload는 기존 결과를 반환하고,
다른 payload는 충돌로 거절한다. 재실행의 received/processing은 resultUnknown으로 조회한다.
저장과 journal은 별도 쓰기이므로 정확히 한 번 실행을 보장하지 않는다. 3초 전달 오류 뒤에는
새 ID 자동 실행 대신 원 ID 상태와 최신 snapshot을 확인한다. snapshot은 실험 ID·revision을 대조한다.

`prepareStart`의 일회성 토큰은 iPhone 단조 시계 기준 3초간 유효하다. 실행 직전 발급·소비하며
늦은 시작·촬영을 막는다. ready 시작과 paused/completed 재개에는 마이크 권한이 필요하고, running 사진 준비는
마이크 권한을 요구하지 않는다. 실제 영상 권한은 후속 CameraSession에서 다시 검사한다.

앱 초기화에서 coordinator를 준비한다. 시작 저장 뒤 전면이면 진행 화면으로, 배경이면 다음 활성화 때
현재 running·실험 ID를 재검증해 이동한다. 다른 실험·등록·편집 충돌은 거절한다. 조회는 진입/저장을
만들지 않고 최초 시작 시각을 보존한다. OS 기동·잠금 접근·강제 종료 후 전달은 보장하지 않는다.
아직 화면을 열지 않은 Watch 시작 요청만 보관하고, 이동 후 지운다. 과거 조회 결과로 이동을 복원하지 않는다.

### #174 음성·공통 기록 전송

`WatchRecordSnapshot/Transport`와 optional response.record를 추가하고 실제 양쪽 WC 라우팅에 연결한다.
`WatchAudioRecorder`는 유한 버퍼로 PCM 구간·manifest를 디스크에 보관하며 OS 중단·용량 오류를 전달한다.
`WatchAudioTransferClient`는 즉시 전송과 파일 전송, receipt·누락 구간 조회로 재전송한다.
iPhone은 callback의 임시 파일을 먼저 복사하고 재기동 때 수신 복사본을 다시 수입한다.

`PhoneWatchAudioService`·`WatchAudioReceiver`·`WatchAudioTranscriber`는 Watch 외부 PCM을 기존
iPhone 마이크 경로와 구분해 전사·저장한다. sequence·범위·무결성·세대/revision을 확인하고, 사용자 수정
전사와 충돌하면 수정본과 원본을 보존해 안내한다. 최종 saved는 실제 저장 ID와 전체 구간 대조 후 발행한다.
구간 ACK·전송 완료·final 전사는 저장 완료가 아니다. 최종 ACK 뒤에도 원본을 자동 삭제하지 않는다.

backend review gate는 명시적 확인/취소를 기다린다. Watch UI의 3초 저장 시계는 #171에서 연결한다.
Watch background audio 설정을 포함한다. 실험 부모의 기록 명령 dispatch/drain은 #269, 실제 Watch
recorder bridge는 #171에서 연결하므로 이 단계의 서비스 구현을 전체 사용자 흐름 완료로 표시하지 않는다.

### #268 타이머 실행·동기화

`WatchTimerMutation`은 start 요청 ID를 타이머 ID로 사용해 중복 시작을 방어한다. 양수 초·Int32 범위와
최대 5개를 검사하고 pause/resume/delete는 targetID로 처리한다. `ExperimentClient/Repository` 및
`SessionTimerFeature`의 기존 저장 경로를 사용한다. 저장 실패는 완료로 바꾸지 않고 재시도 상태를 유지한다.
완료 표시 sidecar는 실험 기록 삭제와 구분한다. endedAt과 자연 완료 시각을 보존한다.

snapshot의 측정 시각으로 남은 시간을 보정하며 실험 pause와 개별 타이머 pause는 별개다.
부모의 공통 record dispatch는 #269, Watch 타이머 View는 #171에서 연결한다.

### #269 사진·영상과 공통 기록 명령·저장 조율

`WatchMediaCommandHandler`가 실험/기록 ID를 검증하고 `CameraCaptureFeature+Watch`로 연결한다.
사진 예약 수용 시각부터 5초를 표시하고 전체 Action에 예약 ID를 전달해 취소 뒤 늦은 촬영을 막는다.
카메라 준비·권한 실패는 응답으로 안내하고 iPhone 준비 후 사용자가 명시적으로 다시 요청한다.
`CameraSession.prepareVideoRecording`은 영상 시작 시 마이크 권한도 재검사한다.

사진 결과 확보, 영상 실제 미리보기 종료 뒤 review/canAutoSave를 제공한다. 명령 전달 3초, 촬영 5초,
review 후 UI 자동 저장 3초는 별개다. 정상 영상 stop과 취소를 구분하고 stop 결과와 confirm 결과 ID를
따로 보관한다. 저장 실패는 살아 있는 같은 원본/recordID로 confirm/cancel을 재시도한다.
`SavedRecords`는 기존 저장소의 실험·ID·type·파일을 확인한 뒤 saved를 재발행하고 journal은 늦은 결과를 보존한다.
사진 RAM·영상 temp는 앱 수명 내 보관이며 강제 종료 뒤 원본 복구를 보장하지 않는다.

App/Session에 이미 구현된 음성·타이머·미디어 명령 dispatch와 응답을 연결한다. pause/complete는
Watch 녹음 보관 barrier와 iPhone 음성·영상 stopAndSave, 사진 예약 취소, 저장 결과를 기다린다.
실패하면 화면 이탈/카메라 deactivate로 먼저 진행하지 않는다. 종료 시 타이머 endedAt을 저장한다.

### #170 Watch 선택·준비와 기록 상태 기반

초기 Store와 실제 Client를 연결해 실험 목록·선택·권한·준비 링·시작 카운트다운·닫기·중단/종료 확인을
제공한다. 카운트다운 직후 새 토큰을 받고 변경 요청을 보낸다. 닫기·타임아웃·stream 종료는 준비 의도를
무효화하고 늦은 시작 응답으로 다른 화면을 열지 않는다. 조회 종료와 미확정 변경 요청을 구분한다.

루트 상태가 참조하는 `WatchRecordFeature/Presentation`과 오류 표시 타입을 함께 제공한다.
진행 도구 View와 실제 recorder bridge는 #171에서 연결한다. 이 head에서 아직 주입되지 않은 bridge를
음성 성공으로 취급하지 않는다. 준비 링은 기존 SVG 자산을 사용한다. 렌더/Figma 일치는 미검증이다.

### #171 Watch 진행 UI·live bridge·pending 복구

실제 `WatchRecordingUIBridge+Live`와 recorder/transfer events를 앱 Store에 주입한다. 진행 도구,
타이머·기록 View·정리 화면을 실제 서비스로 연결한다. saved/cancelled는 실제 결과 뒤에만 종결한다.
review/canAutoSave에서 UI만 3초 저장을 관리하고, 비활성·stream 종료 때 시계를 취소한다.
닫기는 원본 삭제가 아니다. 녹음 연결 끊김은 중지 명령이 아니며 재전송 상태를 별도로 표시한다.

변경 전에 `WatchPendingRequestJournal`에 원 ID·기록별 저장/취소 의도를 원자적으로 보관한다.
재실행은 원 ID 상태 조회부터 수행하고 queriedRequestID·실험·revision을 대조한다. 취소 뒤 늦은 review가
자동 저장을 재개하지 않으며 unknown 취소만 같은 ID로 명시 재전송한다. 다른 실험 복구 기록이 현재
실험 선택을 막지 않는다. 사진 취소 버튼·예약 시각 카운트다운은 실제 취소/복구와 함께 제공한다.

타이머 상태는 iPhone snapshot으로 보정하며 0초 표시만으로 완료를 선언하지 않는다. 모드·프로토콜 단계
메타데이터를 사용하고 순서·중복 시간을 보존한다. 완료 확인/삭제는 기록 endedAt 보존과 구분한다.

### #270 App Intents·Shortcuts·단일 Runtime

세 plain AppIntent와 AppShortcut은 foreground 실행·로컬 기기 인증을 선언한다. `AudioRecordingIntent`는
새로 채택하지 않는다. 앱 진입과 Intent는 `WatchIntentRuntime.shared.store` 하나를 공유하며 화면 버튼의
기존 기록/중지 Action을 사용한다. 가이드 연습은 실제 기록을 만들지 않고, 실험 없는 상태는 실행을 거절한다.

새 remote 촬영은 최신 running 조회와 context lease·실행 토큰을 확인한다. 종료 직후·다른 실험·전면 이탈
뒤 늦은 입력을 차단한다. 녹음 중지/보관은 오프라인 상태도 구분한다. Requests의 lastReadRequestID 완료
갱신 3행을 함께 포함한다. App Shortcut metadata와 실제 OS 목록 노출·실행은 다른 검증이다.
AssistiveTouch의 세 제스처 직접 배정과 단축어 생성 필요 여부는 실기기 확인 전 확정하지 않는다.

## 검증 경계

실제 페어링 WC·Speech·다언어 지연·카메라·권한·잠금·화면 비활성 녹음·Shortcuts OS 실행·
AssistiveTouch 직접 배정·Watch 화면 크기/Figma 렌더는 미실행이다. 실기기가 없고 이 작업은 로컬
재구성 범위다. UI 화면 첨부와 실제 기기 검증은 작성자 잔여 작업이다. 새 7개 head의 CI는 미실행이다.

각 새 head의 실제 명령·exit·로그는 PR 본문 검증 요약과 재구성 manifest에 연결한다.
기존 24개 head 빌드/CI와 freeze 집중 검사 결과를 새 head 성공으로 옮기지 않는다.

최종 원요구 103개 대조는 [요구사항](watch-174/requirements-status.md)을 참고한다.

## iPhone 표시 테마

iPhone 앱은 `Researchers/Info.plist`의 `UIUserInterfaceStyle = Light`로 라이트 테마를 사용한다.
시작 화면과 앱 내 시스템 화면도 같은 표시 정책을 적용받는다.
