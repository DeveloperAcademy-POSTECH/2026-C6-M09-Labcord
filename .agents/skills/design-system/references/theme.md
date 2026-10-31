# 테마·색상

소스: [Theme.swift](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Foundation/Theme.swift), [ColorTokens.swift](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Foundation/ColorTokens.swift).

```swift
content.labcordTheme(LabcordTheme(context: .general))
Text("실험").foregroundStyle(.labcord(.labelPrimary))
```

- 현재 화면은 `.current`, 실험 실행은 `.experiment` 맥락을 사용합니다. `.light`·`.dark`·`.system`은 요구가 있을 때 선택합니다.
- View 안에서는 가까운 테마 환경을 사용합니다. `.system` 색상을 직접 구하면 `color(_:colorScheme:)`에 현재 환경 밝기를 전달합니다.
- Primitive 팔레트는 카탈로그의 Swift 상수입니다. `DesignTokens.json` 로딩·생성 단계를 추가하지 않습니다.
- 원본 대조는 [Foundation](https://www.figma.com/design/Cd0hj5mKHtK0iPZ8AQxuus/LabCord-Design-System?node-id=0-1)과 [Components](https://www.figma.com/design/v6cxQ2I6zURWYQaG5pnuBL?node-id=697-9676)를 구분합니다.
