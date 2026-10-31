# Experiment Title Section

제목과 선행·후행 콘텐츠를 전달합니다.

```swift
ExperimentTitleSection(title: title, layout: .horizontal,
             leading: { leadingContent }, trailing: { trailingContent })
```

- `.vertical`에는 선행 콘텐츠와 제목만 표시합니다. 후행 액션을 보여야 한다면 별도 배치를 결정합니다.
- 가로형은 넓은 원본 배치입니다. 좁은 카탈로그에서 유지할 때는 부모의 가로 ScrollView로 확인하며 전역 최소 폭을 강제하지 않습니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Display/ExperimentTitleSection.swift)
