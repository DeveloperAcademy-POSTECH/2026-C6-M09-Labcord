# Timer Tab Item

부모의 선택 여부와 탭 액션을 전달합니다.

```swift
TimerTabItem(title: title, isSelected: isSelected, action: selectTab)
```

- `isSelected`는 표시 입력입니다. 탭을 누르면 `selectTab`이 부모의 실제 선택을 갱신해야 합니다.
- 두 탭과 개수 표시가 함께 필요하면 [Timer Tabs](timer-tabs.md)를 사용합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/TimerTabItem/TimerTabItem.swift)
