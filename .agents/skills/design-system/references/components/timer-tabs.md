# Timer Tabs

`selection`은 부모의 `TimerTabs.Selection` Binding입니다.

```swift
TimerTabs(selection: $selection, count: runningCount, style: .plain)
```

- 탭은 `.set`·`.running` 선택만 갱신합니다. 표시할 타이머 필터·배열은 부모가 결정합니다.
- 개수는 `.plain`에서 `showCount == true`이고 `count != nil`일 때 표시합니다. `.pill`에는 표시하지 않습니다.
- 개수 값과 탭 제목을 상태 변경마다 새로운 ID로 바꾸지 않습니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/TimerTabs.swift)
