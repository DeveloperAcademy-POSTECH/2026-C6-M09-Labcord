# Experiment List Item

행의 `isSelected` Binding과 실험 열기 액션을 구분해 연결합니다.

```swift
ExperimentListItem(title, date: dateText, status: status,
                   isSelected: $isSelected, onSelect: openExperiment)
```

- 라디오 선택은 Binding을 갱신합니다. `onSelect`는 오른쪽의 실험 열기 버튼이 호출합니다.
- 여러 행의 단일 선택 규칙은 부모에서 ID 기반 Binding으로 연결합니다.
- 큰 글씨에서는 세로 배치를 사용합니다. 호출부에서 행 높이를 고정해 잘라내지 않습니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/ExperimentListItem/ExperimentListItem.swift)
