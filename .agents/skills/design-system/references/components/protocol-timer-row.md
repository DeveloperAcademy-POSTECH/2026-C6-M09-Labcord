# Protocol Timer Row

현재 설정한 `duration: Duration`과 편집 화면을 여는 액션을 전달합니다.

```swift
ProtocolTimerRow(duration, onEdit: openTimerEditor)
```

- 설정 시간은 한국어 단위로 표시하며 시계열 카운트다운을 실행하지 않습니다.
- 연필 버튼은 `onEdit`만 호출합니다. 편집·저장 결과를 반영해 부모가 `duration`을 갱신합니다.
- 표시 정책은 [시간 형식](../time-formatting.md)을 확인합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Timer/ProtocolTimerRow.swift)
