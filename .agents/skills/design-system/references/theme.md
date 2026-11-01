# 색상

소스: [Color set](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Recources/Assets.xcassets/Colors), [리소스 번들](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Foundation/DesignSystemResources.swift).

```swift
let background = Color("General/Background/Primary", bundle: LabcordDesignSystemResources.bundle)
let experimentBackground = Color("Experiment/Background/Primary", bundle: LabcordDesignSystemResources.bundle)
Text("실험")
    .foregroundStyle(Color("General/Label/Primary", bundle: LabcordDesignSystemResources.bundle))
    .background(background)
```

- 색상은 해당 화면에 필요한 General 또는 Experiment 자산을 명시적으로 선택합니다. 배경과 글자색도 각각 지정합니다.
- Primitive 팔레트는 카탈로그의 Swift 상수입니다. `DesignTokens.json` 로딩·생성 단계를 추가하지 않습니다.
- 원본 대조는 [Foundation](https://www.figma.com/design/Cd0hj5mKHtK0iPZ8AQxuus/LabCord-Design-System?node-id=0-1)과 [Components](https://www.figma.com/design/v6cxQ2I6zURWYQaG5pnuBL?node-id=697-9676)를 구분합니다.
