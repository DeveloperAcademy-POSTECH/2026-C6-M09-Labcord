# 모션

소스: [Motion.swift](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Foundation/Motion.swift).

- `LabcordMotion`, `labcordMotion`, `labcordEntrance`, `PressFeedbackButtonStyle`은 공개 API입니다. `labcordPressFeedback`은 모듈 내부에서 사용합니다.
- 즉시 누름 반응, 부드러운 해제, Reduce Motion 분기를 유지합니다.
- 화면 전체에 새 animation을 겹치기보다 변하는 값과 영향받는 하위 View를 확인합니다.
