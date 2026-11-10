import ComposableArchitecture
import SwiftUI

struct WatchGesturePracticeView: View {
    let store: StoreOf<WatchExperimentFeature>

    var body: some View {
        VStack(spacing: 8) {
            Text("제스처 연습")
                .font(.headline)
            Text("이 화면의 버튼과 앱 단축어는 연습 피드백만 제공해요. 실제 녹음·촬영·저장은 하지 않아요.")
                .font(.caption)
            Text("AssistiveTouch의 손 제스처 배정과 실제 실행은 기기 설정에서 확인해주세요.")
                .font(.caption2)
            Button {
                store.send(.practiceRecord(.voice))
            } label: {
                practiceLabel(
                    store.practice.voiceRecording ? "음성 중지 연습" : "음성 시작 연습",
                    completed: store.practice.completedVoice
                )
            }
            .disabled(isBusy)
            Button {
                store.send(.practiceRecord(.photo))
            } label: {
                practiceLabel("사진 촬영 연습", completed: store.practice.completedPhoto)
            }
            .disabled(isBusy)
            Button {
                store.send(.practiceRecord(.video))
            } label: {
                practiceLabel(
                    store.practice.videoRecording ? "영상 중지 연습" : "영상 시작 연습",
                    completed: store.practice.completedVideo
                )
            }
            .disabled(isBusy)
            if let feedback = store.practice.feedback {
                Text(feedback).font(.caption)
            }
            if isBusy {
                Text("진행 중인 기록·요청을 먼저 확인해주세요.").font(.caption)
            }
            Button("닫기") { store.send(.closeTapped) }
        }
        .sensoryFeedback(.success, trigger: store.practice.successCount)
    }

    @ViewBuilder
    private func practiceLabel(_ title: String, completed: Bool) -> some View {
        HStack {
            Text(title)
            if completed {
                Image(systemName: "checkmark")
                    .accessibilityLabel("인식 완료")
            }
        }
    }

    private var isBusy: Bool {
        store.pending != nil || store.isPreparingInterruption
            || store.recording.records.values.contains { !$0.isSettled }
    }
}
