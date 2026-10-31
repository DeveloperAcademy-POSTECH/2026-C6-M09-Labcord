# Loading Indicator

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Feedback/LabcordProgressViewStyle.swift)

불확정 로딩은 native `ProgressView`에 Style을 적용합니다.

```swift
ProgressView("불러오는 중")
    .progressViewStyle(.labcord(size: .medium))
```

- `ProgressView(value:total:)`처럼 완료 비율이 있으면 선형 진행률을 표시합니다.
- Reduce Motion에서는 정적 phase 이미지를 사용합니다. 애니메이션을 바꿀 때 이 분기를 유지합니다.
- 버튼 로딩은 [Button](button.md)·[Icon Button](icon-button.md)의 `isLoading`을 연결합니다.
