# Checkbox

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Input/LabcordCheckboxStyle.swift)

`isIncluded`는 부모가 제공한 선택 `Binding<Bool>`입니다.

```swift
Toggle("실험에 포함", isOn: $isIncluded)
    .toggleStyle(.labcordCheckbox())
```

- `.disabled`·`.controlSize`·`.labelsVisibility`를 native modifier로 적용합니다.
- 표시 레이블을 숨겨도 의미 있는 `Toggle` 제목을 전달합니다. 기존 Toggle 접근성 표현을 유지합니다.
- 별도의 탭 제스처로 Binding을 한 번 더 토글하지 않습니다.
