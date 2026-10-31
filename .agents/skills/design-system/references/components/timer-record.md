# TimerRecord

부모의 설정·누적 `Duration`, 일시정지 횟수, 기록 상태, 세션에 보관한 `identity`를 전달합니다.

```swift
TimerRecord(setDuration: setDuration, elapsedTime: elapsedTime,
            cumulativeTime: cumulativeTime, pauseCount: pauseCount,
            state: recordState, identity: identity)
```

- 기록을 표시하며 시간을 세거나 상태를 전환하지 않습니다. 문자열 overload의 기본값은 시연용입니다.
- 식별색은 상태색이 아닙니다. 세션의 `timerId → LabcordTimerIdentity` 매핑을 모든 실행·일시정지·재개·종료·삭제 기록에서 재사용합니다.
- 식별색 배정은 호출부가 결정하며, 컴포넌트 자체가 색을 배정하지 않습니다.
- 설정 시간은 컴포넌트에서 표시하고, 기록 시각은 함께 사용하는 `TimelineItem`에서 전달합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/TimerRecord/TimerRecord.swift)
