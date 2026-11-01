# Timer Item

부모의 안정적인 `timerID`, 남은/설정 `Duration`, 표시 상태와 액션을 전달합니다.

```swift
TimerItem(timerID, remainingTime: remaining, setDuration: configured,
          format: .hourMinuteSecond, state: state,
          onToggle: toggleTimer, onRemove: removeTimer)
```

- 자체 카운트다운은 없습니다. 부모가 시간과 `.running`·`.paused`·`.completed` 상태를 갱신합니다.
- 진행/일시정지에서는 `onToggle`, 완료에서는 `onRemove`가 호출됩니다.
- [시간 형식](../time-formatting.md)에 맞춰 시분초 포함 여부를 선택하고 긴 값이 잘리지 않는지 확인합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/TimerItem/TimerItem.swift)
