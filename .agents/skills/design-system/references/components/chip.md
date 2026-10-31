# Chip

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/LabcordChipStyle.swift)

`isImportant`는 부모의 `Binding<Bool>`, `removeChip`은 제거 액션입니다.

```swift
LabcordChip(
    isSelected: $isImportant, label: "중요",
    leadingIcon: .check, onDismiss: removeChip
)
```

- 본문 선택과 닫기 액션은 별개입니다. `onDismiss`에서 실제 목록과 선택 상태를 정리합니다.
- 단순 선택은 `Toggle(...).toggleStyle(.labcordChip())`, 액션은 `Button(...).buttonStyle(.labcordChip(isSelected: ...))`로 조합할 수 있습니다.
- ButtonStyle의 `isSelected`는 표시 값이며 선택을 자동 토글하지 않습니다.
- 목록 안의 동작은 [Chip Group](chip-group.md)을 따릅니다.
