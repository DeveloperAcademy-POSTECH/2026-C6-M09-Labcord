# Watch 기록 통합 계약

현재 누적 구현과 각 단계의 연결 경계는 [Watch 구현](../watch-implementation.md)을 따른다.

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

## 원본·저장 경계

음성 archive·수신 복사본은 ACK 뒤에도 자동 삭제하지 않는다. 사진 RAM·영상 temp와 영구 저장 파일을 구분한다.
명령 완료·전사 final·전송 완료를 saved로 승격하지 않는다. 새 보존 기간·삭제·마이그레이션 정책은 추가하지 않는다.
