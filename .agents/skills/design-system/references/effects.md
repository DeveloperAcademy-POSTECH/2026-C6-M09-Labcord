# 효과

소스: [EffectTokens.swift](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Foundation/EffectTokens.swift).

효과 값은 사용하는 화면에 맞게 맥락을 명시합니다.

```swift
let effects = EffectTokens(context: .general)
content.shadow(
    color: Color("General/Effect/Shadow/Soft/Color", bundle: LabcordDesignSystemResources.bundle),
    radius: effects.shadowSoftRadius, y: effects.shadowSoftOffsetY
)
```

- Experiment 효과가 필요하면 `EffectTokens(context: .experiment)`와 해당 색상 자산을 직접 선택합니다.
- 콘텐츠 `.blur(radius:)`와 배경 blur를 같은 표현으로 간주하지 않습니다.
