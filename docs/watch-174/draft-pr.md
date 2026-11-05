# Watch PR 초안 안내

현재 단계는 #171 Watch 진행·기록 화면·실제 연결이다.
진행 도구·타이머·기록 View·정리 화면, 실제 recorder bridge/events, 미확정 요청 journal·재실행·취소·늦은 응답 복구를 담당한다.

WatchExperimentFeature/Requests/Lifecycle/Tools/View를 실제 도구와 pending 복구로 확장한다. App Store에 live bridge를 주입한다. 사진 취소 버튼·카운트다운은 실제 취소·복구와 같은 PR에 둔다.

7개 PR은 #173 → #174 → #268 → #269 → #170 → #171 → #270 순차 stack이다.
첫 base는 `feat/#167-Devin-prepared`, 이후 base는 직전 `feat/#번호-Codex`다.
원격 push·PR 생성·닫힌 PR 재개·이슈 변경·머지는 수행하지 않는다.

실제 새 head와 명령 결과를 포함한 한국어 게시 초안 7개는 재구성 artifact의 `pr-bodies/`에 준비한다.
기본 체크리스트는 직접 확인한 것만 체크하며 실기기·UI 첨부·회귀 미확인을 작성자 잔여 작업으로 남긴다.
