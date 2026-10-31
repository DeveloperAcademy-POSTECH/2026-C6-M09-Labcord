# 카탈로그

소스: [Navigation.swift](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystemCatalog/DesignSystemCatalog+Navigation.swift), [앱 진입점](../../../../LabcordDesignSystemApp/LabcordDesignSystemApp.swift).

- Xcode의 `LabcordDesignSystemApp` 스킴으로 실행합니다. 실제 메뉴와 섹션 테마는 라우팅 소스에서 확인합니다.
- 새 컴포넌트·상태는 개별 메뉴와 해당 섹션 최상단 All에 함께 연결합니다.
- 상태·크기·스타일 선택기로 시연하되 예시 상태·엔진을 제품 도메인 상태로 사용하지 않습니다.
- Primitive 팔레트는 `DesignSystemCatalog+PrimitiveData.swift`의 Swift 값입니다.
- 변경 시 독립 앱 Debug·Release 빌드를 확인합니다. 미디어 재생 예제의 실제 동작과 종료 시 정리는 별도로 확인합니다.
- 빌드·동작 검증은 [verify-change](../../verify-change/SKILL.md)를 따릅니다. 전수 시연표·과거 검증 일지를 추가하지 않습니다.
