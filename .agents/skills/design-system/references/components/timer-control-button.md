# Timer Control Button

현재 표시 상태와 타이머 제어 액션을 전달합니다.

```swift
TimerControlButton(state: timerButtonState, action: openTimerControls)
```

- `.running`은 진행 중 표현입니다. 눌렀다고 상태나 타이머가 자동 전환되지는 않습니다.
- `.disabled`는 입력을 막습니다. `action`에서 실제 설정·제어 흐름을 연결합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Timer/TimerControlButton.swift)
