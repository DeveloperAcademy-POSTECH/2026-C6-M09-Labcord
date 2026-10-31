# ExperimentStatusTimelineItem

실제 상태 변경의 표시 문자열 `eventTitle`과 기록 시각 `timestamp`를 부모가 제공합니다.

```swift
ExperimentStatusTimelineItem(eventTitle, timestamp: timestamp)
```

실험 시작·일시정지·종료 같은 이벤트 행입니다. 자체적으로 상태를 변경하거나 시각을 생성하지 않습니다.
상태 선택·저장은 호출부에서 처리하며 텍스트를 큰 글씨에서도 고정 한 줄로 제한하지 않습니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Record/ExperimentStatusTimelineItem.swift)
