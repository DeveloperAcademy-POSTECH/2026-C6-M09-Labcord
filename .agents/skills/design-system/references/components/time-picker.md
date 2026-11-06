# Timer Picker

부모의 편집 중 시간 Binding을 전달합니다.

```swift
TimerPicker(duration: $draftDuration, usage: .setup)
TimerPicker(duration: $runningDuration) // 기본값: .running
```

- 실험 준비 화면은 `usage: .setup`, 실험 진행 화면은 `usage: .running`을 사용합니다. 기본값은 `.running`이며 `TimerSettingSheet`는 내부에서 `.setup`을 지정합니다.
- `hours`·`minutes`·`seconds` 개별 Binding initializer도 `usage`를 받습니다. 시간은 `0...23`, 분·초는 `0...59` 범위입니다.
- 휠에서 시간은 `0...23`, 분·초는 `0...59`를 선택합니다. 전달받은 Duration은 자동으로 범위에 맞춰지지 않으므로 호출부에서 검증합니다. 취소 가능한 편집은 draft를 씁니다.
- iOS에서는 선택한 행과 이웃 행에 서로 다른 글자 크기·색상을 적용한 휠을 사용합니다. 카운트다운 실행 기능은 없습니다.
- iOS 휠은 양쪽 끝을 넘어가면 같은 단위의 처음이나 끝으로 순환합니다. 각 단위는 독립적으로 바뀌며 다른 단위로 올림·내림하지 않습니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/TimerPicker/TimerPicker.swift)
