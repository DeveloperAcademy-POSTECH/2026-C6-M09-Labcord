# Live Activity 컴포넌트

`LiveActivityContainer`, `LiveActivityContent`, `LiveActivityControlButton`, `LiveActivityStatusIndicator`는 Live Activity 디자인에 사용하기 위한 SwiftUI 뷰입니다.

```swift
LiveActivityContainer {
    LiveActivityContent(
        state: .videoRecording(elapsed: "00:12", progress: 0.4),
        onStop: stopRecording,
        onRetry: retryRecording
    )
}
```

- 콘텐츠 상태는 음성 녹음·영상 녹화·음성 오류·음성 결과·Watch 연결을 구분합니다. 전달한 상태와 콜백에 따라 표시합니다.
- 영상 진행률과 상태 표시기의 진행률은 0...1 범위로 제한합니다. 컨트롤 액션은 호출부가 처리합니다.
- 이 뷰들은 화면 구성 요소입니다. ActivityKit 상태 관리, 위젯 확장, App Intents와 실제 Live Activity 실행은 포함하지 않으며, 위젯 환경 지원도 별도 확인이 필요합니다.

[컨테이너](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/LiveActivity/LiveActivityContainer.swift) · [콘텐츠](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/LiveActivity/LiveActivityContent.swift) · [컨트롤](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/LiveActivity/LiveActivityControlButton.swift) · [상태 표시](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/LiveActivity/LiveActivityStatusIndicator.swift)
