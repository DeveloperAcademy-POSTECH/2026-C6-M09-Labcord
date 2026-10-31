# Radio Button

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/LabcordRadioButton.swift)

`firstSampleID`와 `selectedID`의 값 타입은 같은 `Hashable` 타입입니다. 선택 Binding은 부모가 소유합니다.

```swift
LabcordRadioButton("첫 샘플", value: firstSampleID, selection: $selectedID)
```

- 여러 항목이 같은 선택 Binding을 공유합니다. 값은 모델의 안정적인 ID를 사용합니다.
- 이미 선택한 항목을 다시 눌러도 선택을 해제하지 않습니다. 선택 해제 규칙이 필요하면 호출부에서 별도로 설계합니다.
- 복합 레이블은 `LabcordRadioButton(value:selection:) { ... }`로 전달하고 `.disabled`·`.labelsVisibility`를 유지합니다.
