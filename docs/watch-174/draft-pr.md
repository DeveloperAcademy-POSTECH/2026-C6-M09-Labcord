# Watch PR 초안 안내

현재 단계는 #270 App Intents·공통 실행이다.
세 Intent/Shortcuts 선언, foreground·인증·단일 Store·Runtime·연습 화면·최신 조회/context 검증을 함께 담당한다.

App entry를 Runtime.shared.store로 연결하고 Feature/Tools/View의 Intent action·연습 분기를 확장한다. Requests의 lastReadRequestID 완료 갱신 3행도 이 PR에 포함한다.

7개 PR은 #173 → #174 → #268 → #269 → #170 → #171 → #270 순차 stack이다.
첫 base는 `feat/#167-Devin-prepared`, 이후 base는 직전 `feat/#번호-Codex`다.
원격 push·PR 생성·닫힌 PR 재개·이슈 변경·머지는 수행하지 않는다.

실제 새 head와 명령 결과를 포함한 한국어 게시 초안 7개는 재구성 artifact의 `pr-bodies/`에 준비한다.
기본 체크리스트는 직접 확인한 것만 체크하며 실기기·UI 첨부·회귀 미확인을 작성자 잔여 작업으로 남긴다.
