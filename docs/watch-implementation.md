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
늦은 시작·촬영을 막는다. ready/paused 시작·재개에는 마이크 권한이 필요하고, running 사진 준비는
마이크 권한을 요구하지 않는다. 실제 영상 권한은 후속 CameraSession에서 다시 검사한다.

앱 초기화에서 coordinator를 준비한다. 시작 저장 뒤 전면이면 진행 화면으로, 배경이면 다음 활성화 때
현재 running·실험 ID를 재검증해 이동한다. 다른 실험·등록·편집 충돌은 거절한다. 조회는 진입/저장을
만들지 않고 최초 시작 시각을 보존한다. OS 기동·잠금 접근·강제 종료 후 전달은 보장하지 않는다.

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

## 검증 경계

실제 페어링 WC·Speech·다언어 지연·카메라·권한·잠금·화면 비활성 녹음·Shortcuts OS 실행·
AssistiveTouch 직접 배정·Watch 화면 크기/Figma 렌더는 미실행이다. 실기기가 없고 이 작업은 로컬
재구성 범위다. UI 화면 첨부와 실제 기기 검증은 작성자 잔여 작업이다. 새 7개 head의 CI는 미실행이다.

각 새 head의 실제 명령·exit·로그는 PR 본문 검증 요약과 재구성 manifest에 연결한다.
기존 24개 head 빌드/CI와 freeze 집중 검사 결과를 새 head 성공으로 옮기지 않는다.
