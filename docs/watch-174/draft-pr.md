# Watch PR 초안 안내

현재 단계는 #170 Watch 선택·준비·상태 기반이다.
선택·권한·준비·카운트다운·닫기·관찰 수명을 담당한다. 루트 Feature가 참조하는 WatchRecordFeature/Presentation과 오류 표시 타입을 함께 도입한다.

WatchExperimentFeature/Requests/Lifecycle/View는 선택·준비에 필요한 역사 버전으로 시작한다. App 진입과 준비 링 asset을 포함하고 후속 도구·Intent 참조는 각 단계에서 확장한다.

7개 PR은 #173 → #174 → #268 → #269 → #170 → #171 → #270 순차 stack이다.
첫 base는 `feat/#167-Devin-prepared`, 이후 base는 직전 `feat/#번호-Codex`다.
원격 push·PR 생성·닫힌 PR 재개·이슈 변경·머지는 수행하지 않는다.

실제 새 head와 명령 결과를 포함한 한국어 게시 초안 7개는 재구성 artifact의 `pr-bodies/`에 준비한다.
기본 체크리스트는 직접 확인한 것만 체크하며 실기기·UI 첨부·회귀 미확인을 작성자 잔여 작업으로 남긴다.
