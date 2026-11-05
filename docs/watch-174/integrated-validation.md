# Watch 누적 검증과 남은 조건

현재 기능 범위: #173, #174, #268.

실제 페어링 WC·Speech·다언어 지연·카메라·권한·잠금·화면 비활성 녹음·Shortcuts OS 실행·
AssistiveTouch 직접 배정·Watch 화면 크기/Figma 렌더는 미실행이다. 실기기가 없고 이 작업은 로컬
재구성 범위다. UI 화면 첨부와 실제 기기 검증은 작성자 잔여 작업이다. 새 7개 head의 CI는 미실행이다.

## 증거 구분

- 새 review head: diff 공백·변경 Swift strict lint·해당 정상 scheme·현재 제공되는 check.sh를 실제 실행하고 PR 초안에 결과를 기록한다.
- 기존 freeze: 제품 마지막 코드 `16ace75`, source `6cec726`. 외부 TCA 69개, voice recovery 21조건,
  prepare permission 14조건 등은 당시 결과이며 새 head에서 재실행한 검사로 표시하지 않는다.
- 기존 24개 review head: 정상 scheme 31건·CI 120 checks 성공은 이전 head에만 해당한다.
- 문서/스크립트는 단계에 맞춰 재배치하며 최종 제품/config/resource는 frozen blob+mode와 대조한다.

새 head 로컬 성공은 CI·페어링 기기·UI 픽셀 일치를 입증하지 않는다. 원본·이전 ref와 외부 QA 로그를 보존한다.
