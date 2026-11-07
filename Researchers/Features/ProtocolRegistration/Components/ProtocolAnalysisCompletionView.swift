import LabcordDesignSystem
import SwiftUI

struct ProtocolAnalysisCompletionView: View {
    let onReview: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 48) {
                    ProgressRing(value: 1)
                    VStack(spacing: 8) {
                        Text("프로토콜 분석 완료")
                            .typography(Typography.title3SemiBold)
                        Text("결과를 확인해 보세요.")
                            .typography(Typography.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            Button(action: onReview) {
                Text("분석 결과 보기").frame(maxWidth: .infinity)
            }
            .buttonStyle(.labcord(.primary, size: .large))
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .accessibilityIdentifier("protocol-analysis-completed")
    }
}

#Preview("프로토콜 분석 완료") {
    let _ = FontRegistration.register()
    ProtocolAnalysisCompletionView(onReview: {})
}
