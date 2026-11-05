# Watch PR 초안 안내

현재 단계는 #174 음성 녹음·전사·전송·복구이다.
공통 기록 snapshot/전송 기반과 Watch 녹음·archive·누락 재전송·iPhone 전사·수정 전사 충돌·저장 ACK를 담당한다.

WatchExperimentResponse의 optional record, 양쪽 WCSession 음성·기록 라우팅, WatchExperimentClient의 기록 stream. Watch background audio 설정은 이 PR에 포함한다.

7개 PR은 #173 → #174 → #268 → #269 → #170 → #171 → #270 순차 stack이다.
첫 base는 `feat/#167-Devin-prepared`, 이후 base는 직전 `feat/#번호-Codex`다.
원격 push·PR 생성·닫힌 PR 재개·이슈 변경·머지는 수행하지 않는다.

실제 새 head와 명령 결과를 포함한 한국어 게시 초안 7개는 재구성 artifact의 `pr-bodies/`에 준비한다.
기본 체크리스트는 직접 확인한 것만 체크하며 실기기·UI 첨부·회귀 미확인을 작성자 잔여 작업으로 남긴다.
