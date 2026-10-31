# 시간 표시

소스: [TimerFormatting.swift](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Foundation/TimerFormatting.swift).

```swift
Text(duration, format: .labcordDuration)
Text(duration, format: .labcordClock(includesHours: true)).monospacedDigit()
```

- `duration`은 호출부의 `Duration`입니다. 한국어 단위와 고정 시계 형식을 구분합니다.
- 포맷터는 시간 경과·카운트다운을 실행하지 않습니다. 시간 갱신은 호출부가 소유합니다.
- `TimerDurationFormatStyle().components(duration)`은 마지막 숫자와 단위를 분리할 때 사용합니다.
