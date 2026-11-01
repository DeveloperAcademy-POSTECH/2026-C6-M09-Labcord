# Slide to End Button

실험 종료 제스처의 완료 상태와 액션을 호출부에 연결합니다.

```swift
SlideToEndButton(isTriggered: $isEndTriggered, action: endExperiment)
```

- 제스처가 기준에 도달하거나 접근성 액션을 수행하면 Binding을 `true`로 설정하고 액션을 호출합니다.
- 이미 실행됐거나 비활성화된 경우 다시 호출하지 않습니다. 재시도와 상태 초기화는 호출부가 처리합니다.

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/SlideToEndButton/SlideToEndButton.swift)
