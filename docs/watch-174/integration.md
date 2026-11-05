# Watch 기록 통합 계약

현재 누적 구현과 각 단계의 연결 경계는 [Watch 구현](../watch-implementation.md)을 따른다.

### #270 App Intents·Shortcuts·단일 Runtime

세 plain AppIntent와 AppShortcut은 foreground 실행·로컬 기기 인증을 선언한다. `AudioRecordingIntent`는
새로 채택하지 않는다. 앱 진입과 Intent는 `WatchIntentRuntime.shared.store` 하나를 공유하며 화면 버튼의
기존 기록/중지 Action을 사용한다. 가이드 연습은 실제 기록을 만들지 않고, 실험 없는 상태는 실행을 거절한다.

새 remote 촬영은 최신 running 조회와 context lease·실행 토큰을 확인한다. 종료 직후·다른 실험·전면 이탈
뒤 늦은 입력을 차단한다. 녹음 중지/보관은 오프라인 상태도 구분한다. Requests의 lastReadRequestID 완료
갱신 3행을 함께 포함한다. App Shortcut metadata와 실제 OS 목록 노출·실행은 다른 검증이다.
AssistiveTouch의 세 제스처 직접 배정과 단축어 생성 필요 여부는 실기기 확인 전 확정하지 않는다.

## 원본·저장 경계

음성 archive·수신 복사본은 ACK 뒤에도 자동 삭제하지 않는다. 사진 RAM·영상 temp와 영구 저장 파일을 구분한다.
명령 완료·전사 final·전송 완료를 saved로 승격하지 않는다. 새 보존 기간·삭제·마이그레이션 정책은 추가하지 않는다.
