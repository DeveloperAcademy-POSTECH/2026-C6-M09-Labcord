import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct ProtocolAnalysisCompletionView: View {
    @Bindable var store: StoreOf<ProtocolAnalysisCompletionFeature>
    let requiresReviewConfirmation: Bool
    let reviewConfirmationMessage: String

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
            Button {
                store.send(.reviewTapped(requiresConfirmation: requiresReviewConfirmation))
            } label: {
                Text("분석 결과 보기").frame(maxWidth: .infinity)
            }
            .buttonStyle(.labcord(.primary, size: .large))
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .accessibilityIdentifier("protocol-analysis-completed")
        .alert("타이머와 용어를 확인해 주세요", isPresented: Binding(
            get: { store.showReviewConfirmation },
            set: { if !$0 { store.send(.dismissReviewConfirmation) } }
        )) {
            Button("확인") { store.send(.confirmReview) }
            Button("취소", role: .cancel) { store.send(.dismissReviewConfirmation) }
        } message: {
            Text(reviewConfirmationMessage)
        }
        .alert("프로토콜 분석을 종료할까요?", isPresented: Binding(
            get: { store.showExitConfirmation },
            set: { if !$0 { store.send(.dismissExitConfirmation) } }
        )) {
            Button("분석 종료", role: .destructive) { store.send(.confirmExit) }
            Button("취소", role: .cancel) { store.send(.dismissExitConfirmation) }
        } message: {
            Text("분석을 종료하면 분석 결과가 초기화 돼요.")
        }
    }
}

#Preview("프로토콜 분석 완료") {
    let fontRegistration = FontRegistration.register()
    ProtocolAnalysisCompletionView(
        store: Store(initialState: ProtocolAnalysisCompletionFeature.State()) {
            ProtocolAnalysisCompletionFeature()
        },
        requiresReviewConfirmation: false,
        reviewConfirmationMessage: ""
    )
    .id(fontRegistration)
}
