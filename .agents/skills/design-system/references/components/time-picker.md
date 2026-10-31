# Time Picker

부모의 편집 중 시간 Binding을 전달합니다.

```swift
TimePicker(duration: $draftDuration)
```

- `hours`·`minutes`·`seconds` 개별 Binding initializer도 제공합니다. 시간은 `0...23`, 분·초는 `0...59` 범위입니다.
- 휠에서 시간은 `0...23`, 분·초는 `0...59`를 선택합니다. 전달받은 Duration은 자동으로 범위에 맞춰지지 않으므로 호출부에서 검증합니다. 취소 가능한 편집은 draft를 씁니다.
- iOS는 휠, 다른 지원 플랫폼은 native Picker를 사용합니다. 카운트다운 실행 기능은 없습니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/TimePicker.swift)
