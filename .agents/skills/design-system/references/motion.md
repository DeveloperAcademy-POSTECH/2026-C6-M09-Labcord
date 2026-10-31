# 모션

소스: [Motion.swift](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Foundation/Motion.swift).

- 공유 컴포넌트·카탈로그 내부는 기존 `labcordMotion`·누름 피드백을 재사용합니다. 이 package 내부 API를 제품 앱의 공개 API로 안내하지 않습니다.
- 즉시 누름 반응, 부드러운 해제, Reduce Motion 분기를 유지합니다.
- 화면 전체에 새 animation을 겹치기보다 변하는 값과 영향받는 하위 View를 확인합니다.
