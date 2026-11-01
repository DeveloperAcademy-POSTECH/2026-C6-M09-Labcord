import LabcordDesignSystem
import SwiftUI

struct DesignSystemNewDynamicIslandPage: View {
    let item: CatalogItem

    var body: some View {
        DesignSystemCatalogPage(title: item.title, context: item.context) {
            switch item {
            case .slideToEndButton:
                CatalogSlideToEndScenario()
            case .liveActivityContainer:
                CatalogLiveActivityContainerScenario()
            case .liveActivityContent:
                CatalogLiveActivityContentScenario()
            case .liveActivityControlButton:
                CatalogLiveActivityControlScenario()
            case .liveActivityStatusIndicator:
                CatalogLiveActivityStatusScenario()
            default:
                EmptyView()
            }
        }
    }
}

struct CatalogSlideToEndScenario: View {
    @State private var isTriggered = false
    @State private var actionCount = 0

    var body: some View {
        DesignSystemCatalogCard("Slide to End Button", description: "완료 상태를 확인하는 예시") {
            SlideToEndButton(isTriggered: $isTriggered) { actionCount += 1 }
            Text(isTriggered ? "예시 완료 (\(actionCount)회)" : "오른쪽으로 밀어 주세요")
                .typography(Typography.footnote)
            Button("초기화") { isTriggered = false }
                .buttonStyle(.labcord(.secondary, size: .small))
        }
    }
}

struct CatalogLiveActivityContainerScenario: View {
    var body: some View {
        DesignSystemCatalogCard("Live Activity Container", description: "앱 내부에서 사용하는 컨테이너") {
            LiveActivityContainer {
                Text("기록 중")
                    .foregroundStyle(.white)
            }
        }
    }
}

struct CatalogLiveActivityContentScenario: View {
    @Environment(\.catalogLiveActivityDemo) private var demo
    private enum Example: String, CaseIterable {
        case audioRecording = "음성 녹음"
        case videoRecording = "영상 녹화"
        case audioError = "음성 오류"
        case audioSaving = "음성 저장 중"
        case audioSaved = "음성 저장 완료"
        case watchConnected = "Watch 연결"
    }

    @State private var example = Example.audioRecording
    @State private var progress = 0.4
    @State private var isVideoStopComplete = false
    @State private var lastAction: String?

    var body: some View {
        DesignSystemCatalogCard("Live Activity Content", description: "앱 안에서 상태와 콜백을 확인하는 예시") {
            LiveActivityContainer {
                LiveActivityContent(
                    state: state,
                    isVideoStopComplete: isVideoStopComplete,
                    onStop: { lastAction = "중지 선택" },
                    onRetry: { lastAction = "다시 시도 선택" }
                )
            }
            Picker("상태", selection: $example) {
                ForEach(Example.allCases, id: \.self) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            if example == .videoRecording {
                Toggle("영상 중지 완료", isOn: $isVideoStopComplete)
            }
            if example == .videoRecording || example == .audioSaving {
                Slider(value: $progress, in: 0...1) {
                    Text("진행률")
                }
            }
            if let lastAction {
                Text("예시 동작: \(lastAction)")
                    .typography(Typography.footnote)
            }
            if let demo {
                Button("Dynamic Island 위치에 표시") {
                    demo.show(state: state, isVideoStopComplete: isVideoStopComplete)
                }
                .disabled(demo.devicePlacement == nil)
                Button("표시 닫기") { demo.dismiss() }
            }
        }
        .onDisappear { demo?.dismiss() }
    }

    private var state: LiveActivityContent.State {
        switch example {
        case .audioRecording: .audioRecording(transcript: "실험 내용을 기록하고 있어요.")
        case .videoRecording: .videoRecording(elapsed: "00:12", progress: progress)
        case .audioError: .audioError(message: "인식된 음성이 없습니다.")
        case .audioSaving:
            .audioResult(transcript: "실험 내용을 기록했어요.", isSaving: true, progress: progress)
        case .audioSaved:
            .audioResult(transcript: "실험 내용을 기록했어요.", isSaving: false, progress: 1)
        case .watchConnected: .watchConnected(message: "Apple Watch", detail: "기록할 준비가 됐어요.")
        }
    }
}

struct CatalogLiveActivityControlScenario: View {
    @State private var selectedAction: String?
    @State private var progress = 0.5

    var body: some View {
        DesignSystemCatalogCard("Live Activity Control Button", description: "버튼은 예시 상태만 바꿉니다") {
            HStack(spacing: 12) {
                LiveActivityControlButton(kind: .retry) { selectedAction = "다시 시도" }
                LiveActivityControlButton(kind: .audioStop) { selectedAction = "음성 중지" }
                LiveActivityControlButton(kind: .videoStopComplete) { selectedAction = "영상 중지 완료" }
                LiveActivityControlButton(kind: .videoStopInProgress, progress: progress) {
                    selectedAction = "영상 중지 중"
                }
            }
            Slider(value: $progress, in: 0...1) { Text("진행률") }
            if let selectedAction {
                Text("예시 동작: \(selectedAction)")
                    .typography(Typography.footnote)
            }
        }
    }
}

struct CatalogLiveActivityStatusScenario: View {
    @State private var progress = 0.5

    var body: some View {
        DesignSystemCatalogCard("Live Activity Status Indicator", description: "저장과 연결 상태 표시") {
            HStack(spacing: 12) {
                LiveActivityStatusIndicator(status: .audioSaving, progress: progress)
                LiveActivityStatusIndicator(status: .audioSaved)
                LiveActivityStatusIndicator(status: .watchConnected)
            }
            Slider(value: $progress, in: 0...1) { Text("진행률") }
        }
    }
}

#Preview("Live Activity 카탈로그") {
    _ = FontRegistration.register()
    return NavigationStack {
        DesignSystemNewDynamicIslandPage(item: .liveActivityContent)
    }
}
