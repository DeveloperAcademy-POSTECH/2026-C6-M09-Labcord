# Progress Ring

호출부가 계산한 진행률을 원형 그래프와 백분율로 표시합니다.

```swift
ProgressRing(value: progress)
```

- 기본 색상은 General이며, 어두운 Experiment 영역에서는 `appearance: .experiment`를 지정합니다.
- `progress`는 `Double`이며 0...1 범위로 제한해 표시합니다. 유한하지 않은 값은 0으로 처리합니다.
- 업로드 등 실제 작업과 진행률 갱신은 호출부가 담당합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/ProgressRing/ProgressRing.swift)
