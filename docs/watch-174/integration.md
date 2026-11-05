# Watch 기록 통합 계약

현재 누적 구현과 각 단계의 연결 경계는 [Watch 구현](../watch-implementation.md)을 따른다.

### #268 타이머 실행·동기화

`WatchTimerMutation`은 start 요청 ID를 타이머 ID로 사용해 중복 시작을 방어한다. 양수 초·Int32 범위와
최대 5개를 검사하고 pause/resume/delete는 targetID로 처리한다. `ExperimentClient/Repository` 및
`SessionTimerFeature`의 기존 저장 경로를 사용한다. 저장 실패는 완료로 바꾸지 않고 재시도 상태를 유지한다.
완료 표시 sidecar는 실험 기록 삭제와 구분한다. endedAt과 자연 완료 시각을 보존한다.

snapshot의 측정 시각으로 남은 시간을 보정하며 실험 pause와 개별 타이머 pause는 별개다.
부모의 공통 record dispatch는 #269, Watch 타이머 View는 #171에서 연결한다.

## 원본·저장 경계

음성 archive·수신 복사본은 ACK 뒤에도 자동 삭제하지 않는다. 사진 RAM·영상 temp와 영구 저장 파일을 구분한다.
명령 완료·전사 final·전송 완료를 saved로 승격하지 않는다. 새 보존 기간·삭제·마이그레이션 정책은 추가하지 않는다.
