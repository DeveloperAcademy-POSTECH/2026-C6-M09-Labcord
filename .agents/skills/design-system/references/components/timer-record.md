# TimerRecord

부모의 설정·누적 `Duration`, 일시정지 횟수, 기록 상태, 세션에 보관한 `identity`를 전달합니다.

```swift
TimerRecord(setDuration: setDuration, elapsedTime: elapsedTime,
            cumulativeTime: cumulativeTime, pauseCount: pauseCount,
            state: recordState, identity: identity)
```

- 기록을 표시하며 시간을 세거나 상태를 전환하지 않습니다. 문자열 overload의 기본값은 시연용입니다.
- 식별색은 상태색이 아닙니다. 세션의 `timerId → LabcordTimerIdentity` 매핑을 모든 실행·일시정지·재개·종료·삭제 기록에서 재사용합니다.
- 식별색 배정은 호출부가 결정합니다. 카탈로그 예제는 01→05 순환과 미사용색 우선을 보여 주지만 컴포넌트 자체가 색을 배정하지 않습니다.
- 색 외에 설정 시간과 기록 시각도 표시합니다. 카탈로그 배정 예시는 영구 저장이 아니며 저장 모델 변경을 의미하지 않습니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/TimerRecord.swift) · [배정 예시](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystemCatalog/DesignSystemCatalog+TimerIdentityScenario.swift)
