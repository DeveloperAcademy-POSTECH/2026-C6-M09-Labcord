# Watch PR 초안 안내

현재 단계는 #269 사진·영상·기록 저장 조율이다.
촬영 예약·취소·영상 중지·저장 재시도·실제 저장 파일 조회·미디어 journal과 공통 기록 명령 dispatch·중단/종료 drain을 담당한다.

PhoneWatchExperimentCoordinator+Records, App/Session의 record handler·응답·완료 drain을 이 PR에서 연결한다. 음성 저장 명령과 타이머 dispatch도 이미 준비된 실제 서비스에 연결한다.

7개 PR은 #173 → #174 → #268 → #269 → #170 → #171 → #270 순차 stack이다.
첫 base는 `feat/#167-Devin-prepared`, 이후 base는 직전 `feat/#번호-Codex`다.
원격 push·PR 생성·닫힌 PR 재개·이슈 변경·머지는 수행하지 않는다.

실제 새 head와 명령 결과를 포함한 한국어 게시 초안 7개는 재구성 artifact의 `pr-bodies/`에 준비한다.
기본 체크리스트는 직접 확인한 것만 체크하며 실기기·UI 첨부·회귀 미확인을 작성자 잔여 작업으로 남긴다.
