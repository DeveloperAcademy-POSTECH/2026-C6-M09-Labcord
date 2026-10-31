# TimelineItem

부모가 `title`·`timestamp`와 해당 기록의 `playerContent: View`를 제공합니다.

```swift
TimelineItem(title, timestamp: timestamp, type: .voice) {
    playerContent
}
```

- `type`에 맞는 음성·사진·영상·타이머 콘텐츠를 `ViewBuilder`로 전달합니다. 기본 VoicePlayer·TimerRecord는 시연값입니다.
- 선택은 `state: .selected`로 표시하며 선택 처리·상세 열기는 호출자가 구성합니다.
- `memo`·`showMemo`는 실제 기록값에 연결합니다. 문자열 `timestamp`는 타임스탬프를 읽거나 저장하지 않습니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Record/TimelineItem.swift) · [사용 예시](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystemCatalog/DesignSystemCatalog+Review.swift)
