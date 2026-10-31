# Experiment Control Button

실험 제어 액션과 아이콘 View를 전달합니다.

```swift
ExperimentControlButton(state: controlState, action: resetExperiment) {
    Image(labcordIcon: .arrowsCounterClockwise)
}
```

- `icon` 슬롯은 native ViewBuilder입니다. 실행 의미가 다른 버튼에는 호출부에서 접근성 이름을 지정합니다.
- 상태는 `.default`·`.disabled` 표현이며 실제 실험 초기화·종료는 액션이 처리합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/Experiment/ExperimentControlButton.swift)
