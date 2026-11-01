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

## 앱 안에서 표시

`AnimatedLiveActivityContainer`는 접힌 캡슐과 펼친 콘텐츠 사이의 전환을 표현합니다. 전체 창을 채우는 뷰에 `liveActivityOverlay`를 적용하고, 창 상단 기준 좌표를 `LiveActivityPlacement`로 전달합니다. `forDevice(identifier:)`는 [safearea.info](https://safearea.info/)의 기기별 세로 화면 수치를 사용합니다. 위치가 없거나 가로 화면이면 표시하지 않습니다. 표시 여부, 펼침 상태와 콘텐츠 동작은 호출부에서 관리합니다. `onDismiss`를 전달하면 바깥 터치 또는 접근성 닫기 동작으로 호출부가 닫을 수 있습니다.

카탈로그의 **05 Live Activity**에서 지원 모델의 상단 표시를 확인할 수 있습니다. 펼친 상태는 화면 양옆에 16pt 여백을 둡니다. 이 위치는 시스템 Dynamic Island를 제어하는 값이 아닙니다.

- 카탈로그에서는 세로 화면에 오버레이가 표시되는 동안 상태 막대를 숨기고, 오버레이가 닫히면 다시 표시합니다.
