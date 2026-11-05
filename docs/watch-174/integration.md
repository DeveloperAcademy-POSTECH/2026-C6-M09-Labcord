# Watch 기록 통합 계약

현재 누적 구현과 각 단계의 연결 경계는 [Watch 구현](../watch-implementation.md)을 따른다.

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

## 원본·저장 경계

음성 archive·수신 복사본은 ACK 뒤에도 자동 삭제하지 않는다. 사진 RAM·영상 temp와 영구 저장 파일을 구분한다.
명령 완료·전사 final·전송 완료를 saved로 승격하지 않는다. 새 보존 기간·삭제·마이그레이션 정책은 추가하지 않는다.
