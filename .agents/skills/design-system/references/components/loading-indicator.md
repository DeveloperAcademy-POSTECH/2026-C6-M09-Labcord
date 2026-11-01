# Loading Indicator

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/LoadingIndicator/LoadingIndicatorStyle.swift)

불확정 로딩은 native `ProgressView`에 Style을 적용합니다.

```swift
ProgressView("불러오는 중")
    .progressViewStyle(.labcord(size: .medium))
```

- `ProgressView(value:total:)`처럼 완료 비율이 있으면 선형 진행률을 표시합니다.
- 불확정 로딩의 기본 점 색상은 흰색입니다. 밝은 배경에서는 `foreground:`로 대비되는 색상을 전달합니다.
- Reduce Motion에서는 첫 번째 phase를 정적으로 표시합니다. 애니메이션을 바꿀 때 이 분기를 유지합니다.
- 버튼 로딩은 [Button](button.md)·[Icon Button](icon-button.md)의 `isLoading`을 연결합니다.
