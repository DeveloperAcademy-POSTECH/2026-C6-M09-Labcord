# Accordion

부모의 펼침 Binding과 실제 항목 개수, 콘텐츠를 전달합니다.

```swift
LabcordAccordion("샘플", count: samples.count, isExpanded: $isExpanded) {
    samplesContent
}
```

- `count: Int?`가 `nil`·`0`이면 Count가 숨겨집니다. 전체 숨김은 `showsCount: false`를 씁니다.
- 헤더가 Binding을 토글합니다. `state: .disabled`는 콘텐츠를 접어 보이며 원래 Binding 값을 변경하지 않습니다.
- 콘텐츠의 선택·추가·제거 동작은 각 콘텐츠에 연결합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Experiment/Accordion.swift)
