import LabcordDesignSystem
import SwiftUI

struct EntryLoadingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                ProgressView()
            } else {
                ProgressView()
                    .phaseAnimator([CGFloat(0.8), 1.15]) { content, scale in
                        content.scaleEffect(scale)
                    } animation: { _ in
                        .easeInOut(duration: 0.8)
                    }
            }
        }
        .controlSize(.mini)
        .frame(width: 18, height: 18)
        .accessibilityLabel("실험 저장 중")
    }
}

struct EntryNextButton: View {
    let enabled: Bool
    let retry: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(retry ? "다시 시도" : "다음")
                .font(.body)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.labcord(.primary, size: .large))
        .disabled(!enabled)
        .accessibilityIdentifier("entry-next")
    }
}

struct InvalidationRetryView: View {
    let retry: () -> Void
    let discard: () -> Void

    var body: some View {
        Text("이전 분석을 정리하지 못했어요. 다시 시도해 주세요.")
            .font(.footnote)
        Button("다시 시도", action: retry)
        Button("입력을 버리고 나가기", role: .destructive, action: discard)
    }
}
