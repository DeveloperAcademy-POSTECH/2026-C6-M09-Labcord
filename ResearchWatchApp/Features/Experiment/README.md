# Watch 실험 화면

### #170 Watch 선택·준비와 기록 상태 기반

초기 Store와 실제 Client를 연결해 실험 목록·선택·권한·준비 링·시작 카운트다운·닫기·중단/종료 확인을
제공한다. 카운트다운 직후 새 토큰을 받고 변경 요청을 보낸다. 닫기·타임아웃·stream 종료는 준비 의도를
무효화하고 늦은 시작 응답으로 다른 화면을 열지 않는다. 조회 종료와 미확정 변경 요청을 구분한다.
종료된 실험도 확인 후 재개할 수 있다. iPhone은 기존 기록과 종료 시각을 보존하고 재개 상태 이력을 추가한다.

루트 상태가 참조하는 `WatchRecordFeature/Presentation`과 오류 표시 타입을 함께 제공한다.
진행 도구 View와 실제 recorder bridge는 #171에서 연결한다. 이 head에서 아직 주입되지 않은 bridge를
음성 성공으로 취급하지 않는다. 준비 링은 기존 SVG 자산을 사용한다. 렌더/Figma 일치는 미검증이다.

### #171 Watch 진행 UI·live bridge·pending 복구

실제 `WatchRecordingUIBridge+Live`와 recorder/transfer events를 앱 Store에 주입한다. 진행 도구,
타이머·기록 View·정리 화면을 실제 서비스로 연결한다. saved/cancelled는 실제 결과 뒤에만 종결한다.
review/canAutoSave에서 UI만 3초 저장을 관리하고, 비활성·stream 종료 때 시계를 취소한다.
닫기는 원본 삭제가 아니다. 녹음 연결 끊김은 중지 명령이 아니며 재전송 상태를 별도로 표시한다.
활성 녹음이 없고 양쪽 확인 결과 음성 구간과 완료 정보가 없는 항목은 보존하면서 다시 녹음을 허용한다.

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

## 통신·저장 계약

실제 `WatchExperimentClient`와 DTO를 사용한다. 수신 ACK·처리 결과·영구 저장 ACK를 구분한다.
`requestStatus`의 조회 요청 ID와 원 요청 ID를 대조한다. 오래된 revision·다른 실험 응답으로 화면을 바꾸지 않는다.

실제 페어링 WC·Speech·다언어 지연·카메라·권한·잠금·화면 비활성 녹음·Shortcuts OS 실행·
AssistiveTouch 직접 배정·Watch 화면 크기/Figma 렌더는 미실행이다. 실기기가 없고 이 작업은 로컬
재구성 범위다. UI 화면 첨부와 실제 기기 검증은 작성자 잔여 작업이다. 새 7개 head의 CI는 미실행이다.

전체 계약은 [Watch 구현](../../../docs/watch-implementation.md), 실행 기준은
[검증](../../../docs/watch-174/validation.md)을 참고한다.
