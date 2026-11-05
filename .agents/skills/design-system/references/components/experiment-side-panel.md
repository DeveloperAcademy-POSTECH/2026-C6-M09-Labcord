# Experiment Side Panel

펼침 상태 Binding과 패널 콘텐츠를 전달합니다.

```swift
ExperimentSidePanel(layout: .landscape, isExpanded: $isExpanded) {
    panelContent
}
```

- 화면 방향에 맞는 `layout`은 호출자가 전달합니다. 손잡이는 Binding을 토글합니다.
- 패널 자체가 부모 영역의 아래·후미로 정렬되므로 실제 배치 영역을 부모에서 제한합니다.
- 콘텐츠는 세로형 아래쪽·가로형 후미 방향으로 전환됩니다. 호출부 clipping으로 그림자나 펼침 영역을 자르지 않습니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/ExperimentSidePanel/ExperimentSidePanel.swift)
