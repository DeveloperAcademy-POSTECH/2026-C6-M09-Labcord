# Protocol Timer Item

한국어 시간의 마지막 숫자와 단위를 나눠 전달합니다.

```swift
let parts = TimerDurationFormatStyle().components(duration)
ProtocolTimerItem(value: parts.value, unit: parts.unit, format: .long)
```

- `format`은 글자 크기의 표현이며 문자열을 시간으로 파싱하거나 타이머를 실행하지 않습니다.
- 전체 시간 표시 정책은 [시간 형식](../time-formatting.md)을 확인합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Timer/ProtocolTimerItem.swift)
