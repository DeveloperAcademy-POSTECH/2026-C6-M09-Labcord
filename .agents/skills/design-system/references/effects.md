# 효과

소스: [EffectTokens.swift](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Foundation/EffectTokens.swift), [Theme.swift](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Foundation/Theme.swift).

현재 테마 `theme`과 SwiftUI 환경의 `colorScheme`을 사용합니다.

```swift
let effects = theme.effects(for: colorScheme)
content.shadow(
    color: theme.color(.effectShadowSoftColor, colorScheme: colorScheme),
    radius: effects.shadowSoftRadius, y: effects.shadowSoftOffsetY
)
```

- `.system`에서는 현재 밝기를 전달해 색상과 효과의 맥락이 일치하게 합니다.
- 콘텐츠 `.blur(radius:)`와 배경 blur를 같은 표현으로 간주하지 않습니다.
