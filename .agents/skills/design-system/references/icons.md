# 아이콘

소스: [LabcordIcon.swift](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Icon/LabcordIcon.swift), [Icons.xcassets](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Recources/Icons.xcassets).

```swift
Image(labcordIcon: .plus)
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 24, height: 24)
    .foregroundStyle(.primary)
```

- 아이콘은 일반 SVG 자산입니다. `Image` 크기는 `.frame`으로 지정하며 Symbol 전용 `.font`, `.imageScale`, `.symbolRenderingMode` 동작은 제공하지 않습니다.
- 버튼의 접근성 이름은 호출부에서 지정합니다. 기록 버튼의 캡처 그림은 별도 자산입니다.
- Figma에서 사용한 Phosphor 아이콘의 MIT 고지는 [라이선스](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Recources/Phosphor-LICENSE.txt)를 확인합니다.
