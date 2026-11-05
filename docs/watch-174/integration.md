# Watch 기록 통합 계약

현재 누적 구현과 각 단계의 연결 경계는 [Watch 구현](../watch-implementation.md)을 따른다.

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

## 원본·저장 경계

음성 archive·수신 복사본은 ACK 뒤에도 자동 삭제하지 않는다. 사진 RAM·영상 temp와 영구 저장 파일을 구분한다.
명령 완료·전사 final·전송 완료를 saved로 승격하지 않는다. 새 보존 기간·삭제·마이그레이션 정책은 추가하지 않는다.
