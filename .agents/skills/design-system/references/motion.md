# 모션

소스: [Motion.swift](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Foundation/Motion.swift).

- `LabcordMotion`, `labcordMotion`, `labcordEntrance`, `PressFeedbackButtonStyle`은 공개 API입니다. `labcordPressFeedback`은 모듈 내부에서 사용합니다.
- 즉시 누름 반응, 부드러운 해제, Reduce Motion 분기를 유지합니다.
- 화면 전체에 새 animation을 겹치기보다 변하는 값과 영향받는 하위 View를 확인합니다.
- 현재 모션은 누름 0.18초, 해제 0.3초, 상태 0.22초, 레이아웃 0.34초,
  등장 0.36초, 원위치 복귀 0.28초의 spring response를 사용합니다.
  response는 완료 시점이 아니라 스프링의 반응 속도이며, 상태·복귀는 오버슈트 없이 움직입니다.
- 버튼은 누르는 즉시 반응하고 놓을 때만 복원합니다. 작은 제어는 1%, 일반 버튼은 3%의
  기존 눌림 크기를 유지하며, Reduce Motion에서는 크기 변화 없이 명암으로 반응합니다.
- 아코디언·패널·Live Activity의 펼침은 `.layout`, 슬라이드 취소와 포커스 스크롤은
  `.settle`을 사용합니다. 슬라이드는 손가락을 따라가는 동안 보간하지 않고 놓을 때 복원합니다.
- 진행률·자동 저장·카운트다운의 시간은 호출부가 소유합니다. 이 값들에 일반 스프링을
  덧씌우거나 텍스트 입력·음량·시간 갱신마다 화면 전체를 움직이지 않습니다.
- 시스템 내비게이션·시트·피커의 기본 전환은 유지합니다. 색상·글꼴·간격·최종 크기는
  모션 변경의 대상이 아닙니다.
