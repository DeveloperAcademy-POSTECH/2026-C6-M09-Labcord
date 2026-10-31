# Chip Group

`samples`는 안정적인 ID를 가진 `Identifiable` 배열이며 `selectedIDs`는 같은 ID 타입의 집합입니다.

```swift
ChipGroup(samples, selection: $selectedIDs, label: \.title,
                 onRemove: removeSample, onAdd: addSample)
```

- 칩 본문을 눌러 선택을 토글하지 않습니다. 제거 버튼은 해당 ID를 선택 집합에서 제거하고 `onRemove`를 호출합니다.
- `onRemove`는 실제 배열도 갱신해야 합니다. `onAdd`는 추가 액션이며 새 항목은 부모가 배열에 넣습니다.
- 추가 버튼이 필요 없으면 `onAdd`를 생략합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Input/ChipGroup.swift)
